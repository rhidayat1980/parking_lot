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

// MARK: Transaction Commands

fn begin_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  write_query(sqlight.exec("BEGIN IMMEDIATE;", on: db))
}

fn commit_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  write_query(sqlight.exec("COMMIT;", on: db))
}

fn rollback_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  write_query(sqlight.exec("ROLLBACK;", on: db))
}

// MARK: SQL Error Mapping

fn read_query(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(value) -> Ok(value)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.ReadFailed(message))
  }
}

fn write_query(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(value) -> Ok(value)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.WriteFailed(message))
  }
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

  with_transaction(db, fn() { enter_in_transaction(db, request) })
}

// MARK: Transaction Lifecycle

fn with_transaction(
  db: sqlight.Connection,
  operation: fn() ->
    Result(a, entry_parking_transaction.EntryParkingTransactionError),
) -> Result(a, entry_parking_transaction.EntryParkingTransactionError) {
  use _ <- result.try(
    begin_transaction(db)
    |> result.map_error(entry_parking_transaction.RepositoryFailed),
  )

  finish_transaction(db, operation())
}

fn finish_transaction(
  db: sqlight.Connection,
  operation: Result(a, entry_parking_transaction.EntryParkingTransactionError),
) -> Result(a, entry_parking_transaction.EntryParkingTransactionError) {
  case operation {
    Ok(value) -> commit_or_rollback(db, value)
    Error(operation_error) -> rollback_after_failure(db, operation_error)
  }
}

fn rollback_after_failure(
  db: sqlight.Connection,
  operation_error: entry_parking_transaction.EntryParkingTransactionError,
) -> Result(a, entry_parking_transaction.EntryParkingTransactionError) {
  case rollback_transaction(db) {
    Ok(Nil) -> Error(operation_error)

    Error(rollback_error) ->
      Error(entry_parking_transaction.RollbackFailed(
        operation_error: operation_error,
        rollback_error: rollback_error,
      ))
  }
}

fn commit_or_rollback(
  db: sqlight.Connection,
  value: a,
) -> Result(a, entry_parking_transaction.EntryParkingTransactionError) {
  case commit_transaction(db) {
    Ok(Nil) -> Ok(value)

    Error(commit_error) ->
      rollback_after_failure(
        db,
        entry_parking_transaction.RepositoryFailed(commit_error),
      )
  }
}

// MARK: Entry Operation

fn enter_in_transaction(
  db: sqlight.Connection,
  request: entry_parking.EntryParkingRequest,
) -> Result(
  entry_parking.EntryParkingResult,
  entry_parking_transaction.EntryParkingTransactionError,
) {
  let entry_parking.EntryParkingRequest(vehicle: candidate_vehicle, ..) =
    request

  use _ <- result.try(
    persist_vehicle(db, candidate_vehicle)
    |> result.map_error(entry_parking_transaction.RepositoryFailed),
  )

  let floor_repository = sqlite_floor_repository.new(db)
  let session_repository = sqlite_session_repository.new(db)

  use floors <- result.try(
    sqlite_floor_repository.get_all_floors(floor_repository)
    |> result.map_error(entry_parking_transaction.RepositoryFailed),
  )

  use active_sessions <- result.try(
    sqlite_session_repository.get_active_sessions(session_repository)
    |> result.map_error(entry_parking_transaction.RepositoryFailed),
  )

  use entry_result <- result.try(
    entry_parking.enter_parking(floors, active_sessions, request)
    |> result.map_error(entry_parking_transaction.EntryFailed),
  )

  use _ <- result.try(
    persist_session(db, entry_result.session)
    |> result.map_error(entry_parking_transaction.RepositoryFailed),
  )

  use _ <- result.try(
    persist_ticket(db, entry_result.ticket)
    |> result.map_error(entry_parking_transaction.RepositoryFailed),
  )

  Ok(entry_result)
}

// MARK: Vehicle Persistence

fn persist_vehicle(
  db: sqlight.Connection,
  candidate: vehicle.Vehicle,
) -> Result(Nil, repository_error.RepositoryError) {
  let vehicle_id =
    candidate
    |> vehicle.get_vehicle_id
    |> vehicle.get_vehicle_id_value

  let plate_number =
    candidate
    |> vehicle.get_vehicle_plate_number
    |> vehicle.get_plate_number_value

  let vehicle_type =
    candidate
    |> vehicle.get_vehicle_type
    |> vehicle_type_to_string

  use _ <- result.try(insert_vehicle_if_missing(
    db,
    vehicle_id,
    plate_number,
    vehicle_type,
  ))

  verify_vehicle_identity(db, vehicle_id, plate_number, vehicle_type)
}

fn insert_vehicle_if_missing(
  db: sqlight.Connection,
  vehicle_id: String,
  plate_number: String,
  vehicle_type: String,
) -> Result(Nil, repository_error.RepositoryError) {
  write_query(sqlight.query(
    "
      INSERT INTO vehicles (id, plate_number, vehicle_type)
      VALUES (?, ?, ?)
      ON CONFLICT(id) DO NOTHING;
      ",
    on: db,
    with: [
      sqlight.text(vehicle_id),
      sqlight.text(plate_number),
      sqlight.text(vehicle_type),
    ],
    expecting: decode.string,
  ))
  |> result.map(fn(_) { Nil })
}

fn verify_vehicle_identity(
  db: sqlight.Connection,
  vehicle_id: String,
  plate_number: String,
  vehicle_type: String,
) -> Result(Nil, repository_error.RepositoryError) {
  case
    read_query(sqlight.query(
      "
        SELECT COUNT(*)
        FROM vehicles
        WHERE id = ?
          AND plate_number = ?
          AND vehicle_type = ?;
        ",
      on: db,
      with: [
        sqlight.text(vehicle_id),
        sqlight.text(plate_number),
        sqlight.text(vehicle_type),
      ],
      expecting: decode.field(0, decode.int, fn(value) { decode.success(value) }),
    ))
  {
    Ok([1]) -> Ok(Nil)

    Ok(_) ->
      Error(repository_error.InvalidPersistedData(
        "Vehicle ID already exists with different vehicle data",
      ))

    Error(error) -> Error(error)
  }
}

fn vehicle_type_to_string(vehicle_type: vehicle.VehicleType) -> String {
  case vehicle_type {
    vehicle.Motorcycle -> "Motorcycle"
    vehicle.Car -> "Car"
    vehicle.Truck -> "Truck"
  }
}

// MARK: Session Persistence

fn persist_session(
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

  write_query(sqlight.query(
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

// MARK: Ticket Persistence

fn persist_ticket(
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

  write_query(sqlight.query(
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
