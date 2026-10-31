import application/entry_parking
import application/ports/entry_parking_transaction
import application/ports/repository_error
import domain/parking_session
import domain/parking_slot
import domain/parking_ticket
import domain/vehicle
import gleam/dynamic/decode
import gleam/result
import infrastructure/sqlite_floor_repository
import infrastructure/sqlite_session_repository
import sqlight

// MARK: SQLite Entry Parking Transaction

pub type SqliteEntryParkingTransaction {
  SqliteEntryParkingTransaction(db: sqlight.Connection)
}

// MARK: Constructor

pub fn new(db: sqlight.Connection) -> SqliteEntryParkingTransaction {
  SqliteEntryParkingTransaction(db: db)
}

// MARK: Port Adapter

pub fn to_port(
  repository: SqliteEntryParkingTransaction,
) -> entry_parking_transaction.EntryParkingTransaction {
  entry_parking_transaction.EntryParkingTransaction(enter: fn(request) {
    enter(repository, request)
  })
}

// MARK: Enter Parking

pub fn enter(
  repository: SqliteEntryParkingTransaction,
  request: entry_parking.EntryParkingRequest,
) -> Result(
  entry_parking.EntryParkingResult,
  entry_parking_transaction.EntryParkingTransactionError,
) {
  let SqliteEntryParkingTransaction(db: db) = repository

  case begin_transaction(db) {
    Error(error) -> Error(entry_parking_transaction.RepositoryFailed(error))
    Ok(Nil) ->
      case enter_in_transaction(db, request) {
        Error(error) -> {
          rollback(db)
          Error(error)
        }
        Ok(entry_result) ->
          case commit_transaction(db) {
            Ok(Nil) -> Ok(entry_result)
            Error(error) ->
              Error(entry_parking_transaction.RepositoryFailed(error))
          }
      }
  }
}

// MARK: Entry Operation Inside Transaction

fn enter_in_transaction(
  db: sqlight.Connection,
  request: entry_parking.EntryParkingRequest,
) -> Result(
  entry_parking.EntryParkingResult,
  entry_parking_transaction.EntryParkingTransactionError,
) {
  let floor_repository = sqlite_floor_repository.new(db)
  let session_repository = sqlite_session_repository.new(db)

  case sqlite_floor_repository.get_all_floors(floor_repository) {
    Error(error) -> Error(entry_parking_transaction.RepositoryFailed(error))
    Ok(floors) ->
      case sqlite_session_repository.get_active_sessions(session_repository) {
        Error(error) -> Error(entry_parking_transaction.RepositoryFailed(error))
        Ok(active_sessions) ->
          case entry_parking.enter_parking(floors, active_sessions, request) {
            Error(error) -> Error(entry_parking_transaction.EntryFailed(error))
            Ok(entry_result) -> {
              let entry_parking.EntryParkingResult(
                session: session,
                ticket: ticket,
                ..,
              ) = entry_result

              case insert_session(db, session) {
                Error(error) ->
                  Error(entry_parking_transaction.RepositoryFailed(error))
                Ok(Nil) ->
                  case insert_ticket(db, ticket) {
                    Error(error) ->
                      Error(entry_parking_transaction.RepositoryFailed(error))
                    Ok(Nil) -> Ok(entry_result)
                  }
              }
            }
          }
      }
  }
}

// MARK: Transaction

fn begin_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  query_result(sqlight.exec("BEGIN IMMEDIATE;", on: db))
}

fn commit_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  case query_result(sqlight.exec("COMMIT;", on: db)) {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      rollback(db)
      Error(error)
    }
  }
}

fn rollback(db: sqlight.Connection) {
  let _ = sqlight.exec("ROLLBACK;", on: db)
  Nil
}

// MARK: Insert Session

fn insert_session(
  db: sqlight.Connection,
  session: parking_session.ParkingSession,
) -> Result(Nil, repository_error.RepositoryError) {
  let session_id =
    session
    |> parking_session.get_parking_session_id
    |> parking_session.get_parking_session_id_value

  let vehicle_id =
    session
    |> parking_session.get_parking_session_vehicle_id
    |> vehicle.get_vehicle_id_value

  let slot_id =
    session
    |> parking_session.get_parking_session_slot_id
    |> parking_slot.get_parking_slot_id_value

  let entry_time = parking_session.get_parking_session_entry_time(session)

  query_result(sqlight.query(
    "
    INSERT INTO parking_sessions
      (id, vehicle_id, slot_id, entry_time, exit_time, state)
    VALUES (?, ?, ?, ?, NULL, 'Active');
    ",
    on: db,
    with: [
      sqlight.text(session_id),
      sqlight.text(vehicle_id),
      sqlight.text(slot_id),
      sqlight.int(entry_time),
    ],
    expecting: decode.string,
  ))
  |> result.map(fn(_) { Nil })
}

// MARK: Insert Ticket

fn insert_ticket(
  db: sqlight.Connection,
  ticket: parking_ticket.ParkingTicket,
) -> Result(Nil, repository_error.RepositoryError) {
  let ticket_id =
    ticket
    |> parking_ticket.get_parking_ticket_id
    |> parking_ticket.get_parking_ticket_id_value

  let session_id =
    ticket
    |> parking_ticket.get_parking_ticket_session_id
    |> parking_session.get_parking_session_id_value

  let issued_at = parking_ticket.get_parking_ticket_issued_at(ticket)

  query_result(sqlight.query(
    "
    INSERT INTO parking_tickets (id, session_id, issued_at)
    VALUES (?, ?, ?);
    ",
    on: db,
    with: [
      sqlight.text(ticket_id),
      sqlight.text(session_id),
      sqlight.int(issued_at),
    ],
    expecting: decode.string,
  ))
  |> result.map(fn(_) { Nil })
}

// MARK: Error Mapping

fn query_result(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(value) -> Ok(value)
    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.StorageError(message))
  }
}
