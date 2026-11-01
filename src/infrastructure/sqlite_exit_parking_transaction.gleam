import application/exit_parking
import application/ports/exit_parking_transaction
import application/ports/payment_repository
import application/ports/repository_error
import domain/parking_session
import domain/payment
import gleam/dynamic/decode
import gleam/option
import gleam/result
import infrastructure/sqlite_payment_repository
import infrastructure/sqlite_session_repository
import sqlight

// MARK: SQLite Exit Parking Transaction

pub type SqliteExitParkingTransaction {
  SqliteExitParkingTransaction(db: sqlight.Connection)
}

// MARK: Constructor

pub fn new(db: sqlight.Connection) -> SqliteExitParkingTransaction {
  SqliteExitParkingTransaction(db: db)
}

// MARK: Port Adapter

pub fn to_port(
  repository: SqliteExitParkingTransaction,
) -> exit_parking_transaction.ExitParkingTransaction {
  exit_parking_transaction.ExitParkingTransaction(exit: fn(request) {
    exit(repository, request)
  })
}

// MARK: Exit Parking

pub fn exit(
  repository: SqliteExitParkingTransaction,
  request: exit_parking.ExitParkingRequest,
) -> Result(
  exit_parking.ExitParkingResult,
  exit_parking_transaction.ExitParkingTransactionError,
) {
  let SqliteExitParkingTransaction(db: db) = repository

  with_transaction(db, fn() { exit_in_transaction(db, request) })
}

// MARK: Transaction Lifecycle

fn with_transaction(
  db: sqlight.Connection,
  operation: fn() ->
    Result(a, exit_parking_transaction.ExitParkingTransactionError),
) -> Result(a, exit_parking_transaction.ExitParkingTransactionError) {
  use _ <- result.try(
    begin_transaction(db)
    |> result.map_error(exit_parking_transaction.RepositoryFailed),
  )

  finish_transaction(db, operation())
}

fn finish_transaction(
  db: sqlight.Connection,
  operation: Result(a, exit_parking_transaction.ExitParkingTransactionError),
) -> Result(a, exit_parking_transaction.ExitParkingTransactionError) {
  case operation {
    Ok(value) -> commit_or_rollback(db, value)
    Error(operation_error) -> rollback_after_failure(db, operation_error)
  }
}

fn rollback_after_failure(
  db: sqlight.Connection,
  operation_error: exit_parking_transaction.ExitParkingTransactionError,
) -> Result(a, exit_parking_transaction.ExitParkingTransactionError) {
  case rollback_transaction(db) {
    Ok(Nil) -> Error(operation_error)

    Error(rollback_error) ->
      Error(exit_parking_transaction.RollbackFailed(
        operation_error: operation_error,
        rollback_error: rollback_error,
      ))
  }
}

fn commit_or_rollback(
  db: sqlight.Connection,
  value: a,
) -> Result(a, exit_parking_transaction.ExitParkingTransactionError) {
  case commit_transaction(db) {
    Ok(Nil) -> Ok(value)

    Error(commit_error) ->
      rollback_after_failure(
        db,
        exit_parking_transaction.RepositoryFailed(commit_error),
      )
  }
}

// MARK: Exit Operation

fn exit_in_transaction(
  db: sqlight.Connection,
  request: exit_parking.ExitParkingRequest,
) -> Result(
  exit_parking.ExitParkingResult,
  exit_parking_transaction.ExitParkingTransactionError,
) {
  let exit_parking.ExitParkingRequest(session_id: session_id, ..) = request

  let session_repository = sqlite_session_repository.new(db)

  use session <- result.try(load_session(session_repository, session_id))

  use exit_result <- result.try(
    exit_parking.exit_parking(session, request)
    |> result.map_error(exit_parking_transaction.ExitFailed),
  )

  use _ <- result.try(
    persist_payment(db, exit_result.payment)
    |> result.map_error(exit_parking_transaction.RepositoryFailed),
  )

  use _ <- result.try(
    persist_closed_session(db, exit_result.session)
    |> result.map_error(exit_parking_transaction.RepositoryFailed),
  )

  Ok(exit_result)
}

// MARK: Session Loading

fn load_session(
  repository: sqlite_session_repository.SqliteSessionRepository,
  session_id: parking_session.ParkingSessionId,
) -> Result(
  parking_session.ParkingSession,
  exit_parking_transaction.ExitParkingTransactionError,
) {
  use session <- result.try(
    sqlite_session_repository.get_session(repository, session_id)
    |> result.map_error(exit_parking_transaction.RepositoryFailed),
  )

  case session {
    option.Some(value) -> Ok(value)

    option.None ->
      Error(exit_parking_transaction.ExitFailed(exit_parking.SessionNotFound))
  }
}

// MARK: Payment Persistence

fn persist_payment(
  db: sqlight.Connection,
  payment_option: option.Option(payment.Payment),
) -> Result(Nil, repository_error.RepositoryError) {
  case payment_option {
    option.None -> Ok(Nil)

    option.Some(value) -> {
      let repository = sqlite_payment_repository.new(db)
      let payment_repository = sqlite_payment_repository.to_port(repository)

      let payment_repository.PaymentRepository(save_payment: save_payment, ..) =
        payment_repository

      save_payment(value)
    }
  }
}

// MARK: Session Persistence

fn persist_closed_session(
  db: sqlight.Connection,
  session: parking_session.ParkingSession,
) -> Result(Nil, repository_error.RepositoryError) {
  let session_id =
    session
    |> parking_session.get_parking_session_id
    |> parking_session.get_parking_session_id_value

  let exit_time = parking_session.get_parking_session_exit_time(session)

  case exit_time {
    option.None ->
      Error(repository_error.InvalidPersistedData(
        "Cannot persist a closed session without an exit time",
      ))

    option.Some(value) ->
      case
        query_result(sqlight.query(
          "
        UPDATE parking_sessions
        SET
          exit_time = ?,
          state = 'Closed'
        WHERE id = ?
          AND state = 'Active'
        RETURNING id;
        ",
          on: db,
          with: [
            sqlight.int(value),
            sqlight.text(session_id),
          ],
          expecting: decode.field(0, decode.string, fn(id) {
            decode.success(id)
          }),
        ))
      {
        Ok([saved_id]) if saved_id == session_id -> Ok(Nil)

        Ok(_) ->
          Error(repository_error.WriteFailed(
            "Failed to persist closed parking session",
          ))

        Error(error) -> Error(error)
      }
  }
}

// MARK: Transaction Commands

fn begin_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  query_result(sqlight.exec("BEGIN IMMEDIATE;", on: db))
}

fn commit_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  query_result(sqlight.exec("COMMIT;", on: db))
}

fn rollback_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  query_result(sqlight.exec("ROLLBACK;", on: db))
}

// MARK: SQL Error Mapping

fn query_result(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(value) -> Ok(value)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.WriteFailed(message))
  }
}
