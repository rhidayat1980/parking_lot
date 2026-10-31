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
import sqlight

// MARK: Test Helpers

fn setup_database() -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(Nil) =
    sqlight.exec(
      "
      CREATE TABLE vehicles (
        id TEXT PRIMARY KEY NOT NULL
      );

      CREATE TABLE parking_floors (
        id TEXT PRIMARY KEY NOT NULL
      );

      CREATE TABLE parking_slots (
        id TEXT PRIMARY KEY NOT NULL,
        floor_id TEXT NOT NULL,
        supported_vehicle_type TEXT NOT NULL,
        FOREIGN KEY (floor_id) REFERENCES parking_floors(id)
      );

      CREATE TABLE parking_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        vehicle_id TEXT NOT NULL,
        slot_id TEXT NOT NULL,
        entry_time INTEGER NOT NULL,
        exit_time INTEGER,
        state TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles(id),
        FOREIGN KEY (slot_id) REFERENCES parking_slots(id)
      );

      CREATE TABLE parking_tickets (
        id TEXT PRIMARY KEY NOT NULL,
        session_id TEXT NOT NULL UNIQUE,
        issued_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES parking_sessions(id)
      );
      ",
      on: db,
    )

  let assert Ok(Nil) =
    sqlight.exec(
      "
      INSERT INTO vehicles (id)
      VALUES ('VEHICLE-001');

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
  let assert Ok(vehicle_id) = vehicle.new_vehicle_id(id)
  let assert Ok(plate_number) = vehicle.new_plate_number("B 1234 ABC")

  vehicle.new_vehicle(vehicle_id, plate_number, vehicle.Car)
}

fn make_request(
  session_id: String,
  ticket_id: String,
  vehicle_id: String,
) -> entry_parking.EntryParkingRequest {
  let assert Ok(session) = parking_session.new_parking_session_id(session_id)
  let assert Ok(ticket) = parking_ticket.new_parking_ticket_id(ticket_id)

  entry_parking.EntryParkingRequest(
    session_id: session,
    ticket_id: ticket,
    vehicle: make_vehicle(vehicle_id),
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
      ('SESSION-EXISTING', 'VEHICLE-001', 'SLOT-EXISTING', 100, 200, 'Completed');

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
