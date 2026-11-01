import application/ports/payment_repository
import application/ports/repository_error
import domain/parking_session
import domain/payment
import gleam/dynamic/decode
import gleam/option
import gleam/result
import sqlight

pub type SqlitePaymentRepository {
  SqlitePaymentRepository(db: sqlight.Connection)
}

// -----------------------------------------------------------------------------
// Persistence model
// -----------------------------------------------------------------------------

type PaymentRow {
  PaymentRow(
    id: String,
    session_id: String,
    amount: Int,
    method: String,
    status: String,
    created_at: Int,
  )
}

// -----------------------------------------------------------------------------
// Constructor
// -----------------------------------------------------------------------------

pub fn new(db: sqlight.Connection) -> SqlitePaymentRepository {
  SqlitePaymentRepository(db: db)
}

// -----------------------------------------------------------------------------
// Port adapter
// -----------------------------------------------------------------------------

pub fn to_port(
  repository: SqlitePaymentRepository,
) -> payment_repository.PaymentRepository {
  payment_repository.PaymentRepository(
    get_payment: fn(id) { get_payment(repository, id) },
    save_payment: fn(value) { save_payment(repository, value) },
  )
}

// -----------------------------------------------------------------------------
// Repository operations
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// Error mapping
// -----------------------------------------------------------------------------

fn read_query(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(result) -> Ok(result)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.ReadFailed(message))
  }
}

fn write_query(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(result) -> Ok(result)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.WriteFailed(message))
  }
}

pub fn get_payment(
  repository: SqlitePaymentRepository,
  id: payment.PaymentId,
) -> Result(option.Option(payment.Payment), repository_error.RepositoryError) {
  let SqlitePaymentRepository(db: db) = repository

  use rows <- result.try(load_payment(db, id))

  case rows {
    [] -> Ok(option.None)

    [row] -> {
      use value <- result.try(payment_row_to_domain(row))
      Ok(option.Some(value))
    }

    [_, _, ..] ->
      Error(repository_error.InvalidPersistedData(
        "Multiple payments found for one payment ID",
      ))
  }
}

pub fn save_payment(
  repository: SqlitePaymentRepository,
  value: payment.Payment,
) -> Result(Nil, repository_error.RepositoryError) {
  let SqlitePaymentRepository(db: db) = repository

  let payment_id = payment.get_payment_id_value(payment.get_payment_id(value))

  let session_id =
    parking_session.get_parking_session_id_value(payment.get_payment_session_id(
      value,
    ))

  let amount = payment.get_payment_amount(value)
  let method = payment.get_payment_method(value)
  let status = payment.get_payment_status(value)
  let created_at = payment.get_payment_created_at(value)

  let method_value = payment_method_to_string(method)
  let status_value = payment_status_to_string(status)

  use saved_ids <- result.try(
    write_query(sqlight.query(
      "
        INSERT INTO payments (
          id,
          session_id,
          amount,
          method,
          status,
          created_at
        )
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          session_id = excluded.session_id,
          amount = excluded.amount,
          method = excluded.method,
          status = excluded.status,
          created_at = excluded.created_at
        RETURNING id;
        ",
      on: db,
      with: [
        sqlight.text(payment_id),
        sqlight.text(session_id),
        sqlight.int(amount),
        sqlight.text(method_value),
        sqlight.text(status_value),
        sqlight.int(created_at),
      ],
      expecting: decode.field(0, decode.string, fn(id) { decode.success(id) }),
    )),
  )

  case saved_ids {
    [saved_id] if saved_id == payment_id -> Ok(Nil)

    _ -> Error(repository_error.WriteFailed("Failed to persist payment"))
  }
}

// -----------------------------------------------------------------------------
// Database queries
// -----------------------------------------------------------------------------

fn load_payment(
  db: sqlight.Connection,
  id: payment.PaymentId,
) -> Result(List(PaymentRow), repository_error.RepositoryError) {
  read_query(sqlight.query(
    "
      SELECT
        id,
        session_id,
        amount,
        method,
        status,
        created_at
      FROM payments
      WHERE id = ?;
      ",
    on: db,
    with: [
      sqlight.text(payment.get_payment_id_value(id)),
    ],
    expecting: payment_row_decoder(),
  ))
}

// -----------------------------------------------------------------------------
// Persistence decoder
// -----------------------------------------------------------------------------

fn payment_row_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(id) {
    decode.at([1], decode.string)
    |> decode.then(fn(session_id) {
      decode.at([2], decode.int)
      |> decode.then(fn(amount) {
        decode.at([3], decode.string)
        |> decode.then(fn(method) {
          decode.at([4], decode.string)
          |> decode.then(fn(status) {
            decode.at([5], decode.int)
            |> decode.map(fn(created_at) {
              PaymentRow(
                id: id,
                session_id: session_id,
                amount: amount,
                method: method,
                status: status,
                created_at: created_at,
              )
            })
          })
        })
      })
    })
  })
}

// -----------------------------------------------------------------------------
// Persistence -> Domain mapping
// -----------------------------------------------------------------------------

fn payment_row_to_domain(
  row: PaymentRow,
) -> Result(payment.Payment, repository_error.RepositoryError) {
  let PaymentRow(
    id: payment_id,
    session_id: session_id,
    amount: amount,
    method: method,
    status: status,
    created_at: created_at,
  ) = row

  use id <- result.try(restore_payment_id(payment_id))
  use session_id <- result.try(restore_session_id(session_id))
  use method <- result.try(restore_payment_method(method))

  use value <- result.try(restore_payment(
    id,
    session_id,
    amount,
    method,
    created_at,
  ))

  restore_payment_status(value, status)
}

fn restore_payment_id(
  value: String,
) -> Result(payment.PaymentId, repository_error.RepositoryError) {
  case payment.new_payment_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(repository_error.InvalidPersistedData(payment.error_message(error)))
  }
}

fn restore_session_id(
  value: String,
) -> Result(parking_session.ParkingSessionId, repository_error.RepositoryError) {
  case parking_session.new_parking_session_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(
        repository_error.InvalidPersistedData(parking_session.error_message(
          error,
        )),
      )
  }
}

fn restore_payment_method(
  value: String,
) -> Result(payment.PaymentMethod, repository_error.RepositoryError) {
  case value {
    "Cash" -> Ok(payment.Cash)
    "Qris" -> Ok(payment.Qris)
    "DebitCard" -> Ok(payment.DebitCard)
    "EWallet" -> Ok(payment.EWallet)

    _ ->
      Error(repository_error.InvalidPersistedData(
        "Invalid payment method in database",
      ))
  }
}

fn restore_payment(
  id: payment.PaymentId,
  session_id: parking_session.ParkingSessionId,
  amount: Int,
  method: payment.PaymentMethod,
  created_at: Int,
) -> Result(payment.Payment, repository_error.RepositoryError) {
  case payment.new_payment(id, session_id, amount, method, created_at) {
    Ok(value) -> Ok(value)

    Error(error) ->
      Error(repository_error.InvalidPersistedData(payment.error_message(error)))
  }
}

// -----------------------------------------------------------------------------
// Domain state restoration
// -----------------------------------------------------------------------------

fn restore_payment_status(
  value: payment.Payment,
  status: String,
) -> Result(payment.Payment, repository_error.RepositoryError) {
  case status {
    "Pending" -> Ok(value)

    "Succeeded" -> restore_state_transition(value, payment.succeed_payment)

    "Failed" -> restore_state_transition(value, payment.fail_payment)

    "Cancelled" -> restore_state_transition(value, payment.cancel_payment)

    _ ->
      Error(repository_error.InvalidPersistedData(
        "Invalid payment status in database",
      ))
  }
}

fn restore_state_transition(
  value: payment.Payment,
  transition: fn(payment.Payment) ->
    Result(payment.Payment, payment.PaymentError),
) -> Result(payment.Payment, repository_error.RepositoryError) {
  case transition(value) {
    Ok(updated) -> Ok(updated)

    Error(error) ->
      Error(repository_error.InvalidPersistedData(payment.error_message(error)))
  }
}

// -----------------------------------------------------------------------------
// Domain -> Persistence conversion
// -----------------------------------------------------------------------------

fn payment_method_to_string(method: payment.PaymentMethod) -> String {
  case method {
    payment.Cash -> "Cash"
    payment.Qris -> "Qris"
    payment.DebitCard -> "DebitCard"
    payment.EWallet -> "EWallet"
  }
}

fn payment_status_to_string(status: payment.PaymentStatus) -> String {
  case status {
    payment.Pending -> "Pending"
    payment.Succeeded -> "Succeeded"
    payment.Failed -> "Failed"
    payment.Cancelled -> "Cancelled"
  }
}
