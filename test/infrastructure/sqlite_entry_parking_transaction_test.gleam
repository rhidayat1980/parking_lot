import application/entry_parking
import application/ports/entry_parking_transaction
import application/ports/repository_error
import domain/parking_session
import domain/parking_ticket
import domain/vehicle
import gleam/dynamic/decode
import gleeunit/should
import infrastructure/sqlite_connection
import infrastructure/sqlite_entry_parking_transaction
import simplifile
import sqlight

// MARK: Test Helpers

fn setup_database() -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(migration_sql) =
    simplifile.read(
      from: "priv/repo/migrations/001_create_parking_schema.up.sql",
    )

  let assert Ok(Nil) = sqlight.exec(migration_sql, on: db)

  let assert Ok(Nil) =
    sqlight.exec(
      "
      INSERT INTO vehicles (id, plate_number, vehicle_type)
      VALUES ('VEHICLE-001', 'B 1234 ABC', 'Car');

      INSERT INTO parking_floors (id)
      VALUES ('FLOOR-001');

      INSERT INTO parking_slots (id, floor_id, supported_vehicle_type)
      VALUES ('SLOT-001', 'FLOOR-001', 'Car');
      ",
      on: db,
    )

  db
}

fn execute(db: sqlight.Connection, sql: String) -> Nil {
  let assert Ok(Nil) = sqlight.exec(sql, on: db)
  Nil
}

fn make_vehicle(id: String) -> vehicle.Vehicle {
  make_vehicle_with_details(id, "B 1234 ABC", vehicle.Car)
}

fn make_vehicle_with_details(
  id: String,
  plate: String,
  vehicle_type: vehicle.VehicleType,
) -> vehicle.Vehicle {
  let assert Ok(vehicle_id) = vehicle.new_vehicle_id(id)
  let assert Ok(plate_number) = vehicle.new_plate_number(plate)

  vehicle.new_vehicle(vehicle_id, plate_number, vehicle_type)
}

fn make_request(
  session_id: String,
  ticket_id: String,
  vehicle_id: String,
) -> entry_parking.EntryParkingRequest {
  make_request_with_vehicle(session_id, ticket_id, make_vehicle(vehicle_id))
}

fn make_request_with_vehicle(
  session_id: String,
  ticket_id: String,
  candidate_vehicle: vehicle.Vehicle,
) -> entry_parking.EntryParkingRequest {
  let assert Ok(session) = parking_session.new_parking_session_id(session_id)
  let assert Ok(ticket) = parking_ticket.new_parking_ticket_id(ticket_id)

  entry_parking.EntryParkingRequest(
    session_id: session,
    ticket_id: ticket,
    vehicle: candidate_vehicle,
    entry_time: 1000,
  )
}

fn count_rows(db: sqlight.Connection, table: String) -> Int {
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) FROM " <> table <> ";",
      on: db,
      with: [],
      expecting: decode.field(0, decode.int, fn(value) { decode.success(value) }),
    )

  count
}

fn close_database(db: sqlight.Connection) -> Nil {
  let assert Ok(Nil) = sqlight.close(db)
  Nil
}

fn make_existing_completed_session(db: sqlight.Connection) -> Nil {
  execute(
    db,
    "
    INSERT INTO parking_slots (id, floor_id, supported_vehicle_type)
    VALUES ('SLOT-EXISTING', 'FLOOR-001', 'Car');

    INSERT INTO parking_sessions
      (id, vehicle_id, slot_id, entry_time, exit_time, state)
    VALUES
      ('SESSION-EXISTING', 'VEHICLE-001', 'SLOT-EXISTING', 100, 200, 'Closed');

    INSERT INTO parking_tickets (id, session_id, issued_at)
    VALUES ('TICKET-DUPLICATE', 'SESSION-EXISTING', 100);
    ",
  )
}

// MARK: Successful Transaction

pub fn entry_persists_session_and_ticket_test() {
  let db = setup_database()
  let transaction = sqlite_entry_parking_transaction.new(db)

  let request = make_request("SESSION-001", "TICKET-001", "VEHICLE-001")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Ok(entry_result) -> {
      parking_session.get_parking_session_state(entry_result.session)
      |> should.equal(parking_session.Active)

      parking_ticket.get_parking_ticket_issued_at(entry_result.ticket)
      |> should.equal(1000)
    }
    Error(_) -> should.fail()
  }

  count_rows(db, "parking_sessions")
  |> should.equal(1)

  count_rows(db, "parking_tickets")
  |> should.equal(1)

  close_database(db)
}

// MARK: Vehicle Persistence

pub fn entry_persists_new_vehicle_test() {
  let db = setup_database()
  let transaction = sqlite_entry_parking_transaction.new(db)

  let request = make_request("SESSION-NEW", "TICKET-NEW", "VEHICLE-002")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }

  count_rows(db, "vehicles")
  |> should.equal(2)

  count_rows(db, "parking_sessions")
  |> should.equal(1)

  count_rows(db, "parking_tickets")
  |> should.equal(1)

  close_database(db)
}

pub fn entry_reuses_existing_vehicle_with_same_identity_test() {
  let db = setup_database()
  let transaction = sqlite_entry_parking_transaction.new(db)

  let request = make_request("SESSION-001", "TICKET-001", "VEHICLE-001")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }

  // Existing vehicle must not be duplicated.
  count_rows(db, "vehicles")
  |> should.equal(1)

  count_rows(db, "parking_sessions")
  |> should.equal(1)

  close_database(db)
}

pub fn entry_rejects_vehicle_id_with_different_identity_test() {
  let db = setup_database()
  let transaction = sqlite_entry_parking_transaction.new(db)

  let conflicting_vehicle =
    make_vehicle_with_details("VEHICLE-001", "B 9999 XYZ", vehicle.Car)

  let request =
    make_request_with_vehicle("SESSION-001", "TICKET-001", conflicting_vehicle)

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // The original vehicle must remain unchanged.
  count_rows(db, "vehicles")
  |> should.equal(1)

  // No session or ticket should be created.
  count_rows(db, "parking_sessions")
  |> should.equal(0)

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}

// MARK: Rollback

pub fn entry_rolls_back_session_when_ticket_insert_fails_test() {
  let db = setup_database()
  make_existing_completed_session(db)

  let transaction = sqlite_entry_parking_transaction.new(db)

  // The slot is available, so allocation succeeds.
  // Inserting the duplicate ticket ID then fails.
  let request = make_request("SESSION-NEW", "TICKET-DUPLICATE", "VEHICLE-001")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // Only the pre-existing completed session must remain.
  count_rows(db, "parking_sessions")
  |> should.equal(1)

  // Only the pre-existing ticket must remain.
  count_rows(db, "parking_tickets")
  |> should.equal(1)

  close_database(db)
}

pub fn entry_rolls_back_new_vehicle_when_ticket_insert_fails_test() {
  let db = setup_database()
  make_existing_completed_session(db)

  let transaction = sqlite_entry_parking_transaction.new(db)

  // VEHICLE-002 does not exist before this transaction.
  // The duplicate ticket causes the transaction to fail.
  let request = make_request("SESSION-NEW", "TICKET-DUPLICATE", "VEHICLE-002")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // The newly inserted vehicle must also be rolled back.
  count_rows(db, "vehicles")
  |> should.equal(1)

  // Existing records must remain unchanged.
  count_rows(db, "parking_sessions")
  |> should.equal(1)

  count_rows(db, "parking_tickets")
  |> should.equal(1)

  close_database(db)
}

pub fn entry_rolls_back_when_session_insert_fails_test() {
  let db = setup_database()

  // Seed a session with the same ID as the incoming request.
  // The transaction should fail when inserting the new session.
  execute(
    db,
    "
    INSERT INTO parking_sessions
      (id, vehicle_id, slot_id, entry_time, exit_time, state)
    VALUES
      ('SESSION-DUPLICATE', 'VEHICLE-001', 'SLOT-001', 100, 200, 'Closed');
    ",
  )

  let transaction = sqlite_entry_parking_transaction.new(db)

  let request = make_request("SESSION-DUPLICATE", "TICKET-NEW", "VEHICLE-001")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // The pre-existing session must remain the only session.
  count_rows(db, "parking_sessions")
  |> should.equal(1)

  // No ticket should be inserted.
  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}

// MARK: Connection Remains Usable

pub fn connection_remains_usable_after_rollback_test() {
  let db = setup_database()
  make_existing_completed_session(db)

  let transaction = sqlite_entry_parking_transaction.new(db)

  let failed_request =
    make_request("SESSION-FAILED", "TICKET-DUPLICATE", "VEHICLE-001")

  let failed_result =
    sqlite_entry_parking_transaction.enter(transaction, failed_request)

  case failed_result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // A new entry on the same connection should still work after rollback.
  let next_request = make_request("SESSION-NEXT", "TICKET-NEXT", "VEHICLE-001")

  let next_result =
    sqlite_entry_parking_transaction.enter(transaction, next_request)

  case next_result {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }

  count_rows(db, "parking_sessions")
  |> should.equal(2)

  count_rows(db, "parking_tickets")
  |> should.equal(2)

  close_database(db)
}

// MARK: Repository Failures

pub fn entry_fails_when_floor_repository_fails_test() {
  let db = setup_database()

  // Rename the original table so the repository query cannot find it.
  execute(db, "ALTER TABLE parking_floors RENAME TO parking_floors_backup;")

  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request("SESSION-001", "TICKET-001", "VEHICLE-001")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  count_rows(db, "parking_sessions")
  |> should.equal(0)

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}

pub fn entry_fails_when_session_repository_fails_test() {
  let db = setup_database()

  // Rename the table so the session repository query fails.
  execute(db, "ALTER TABLE parking_sessions RENAME TO parking_sessions_backup;")

  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request("SESSION-001", "TICKET-001", "VEHICLE-001")

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}
