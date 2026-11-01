import application/entry_parking
import application/ports/entry_parking_transaction
import application/ports/repository_error
import domain/parking_session
import domain/parking_slot
import domain/parking_ticket
import domain/vehicle
import gleam/dynamic/decode
import gleeunit/should
import infrastructure/sqlite_connection
import infrastructure/sqlite_entry_parking_transaction
import simplifile
import sqlight

// MARK: Test Helpers

fn setup_database(with_slot: Bool) -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(initial_migration) =
    simplifile.read(
      from: "priv/repo/migrations/001_create_parking_schema.up.sql",
    )

  let assert Ok(Nil) = sqlight.exec(initial_migration, on: db)

  case with_slot {
    True -> {
      let assert Ok(Nil) =
        sqlight.exec(
          "
          INSERT INTO parking_floors (id)
          VALUES ('FLOOR-001');

          INSERT INTO parking_slots
            (id, floor_id, supported_vehicle_type)
          VALUES
            ('SLOT-001', 'FLOOR-001', 'Car');
          ",
          on: db,
        )
      Nil
    }

    False -> Nil
  }

  db
}

fn execute(db: sqlight.Connection, sql: String) {
  let assert Ok(Nil) = sqlight.exec(sql, on: db)
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

fn get_session_state(db: sqlight.Connection) -> String {
  let assert Ok([state]) =
    sqlight.query(
      "SELECT state FROM parking_sessions WHERE id = 'SESSION-001';",
      on: db,
      with: [],
      expecting: decode.field(0, decode.string, fn(value) {
        decode.success(value)
      }),
    )

  state
}

fn make_vehicle(
  id: String,
  plate_number: String,
  vehicle_type: vehicle.VehicleType,
) -> vehicle.Vehicle {
  let assert Ok(vehicle_id) = vehicle.new_vehicle_id(id)
  let assert Ok(plate) = vehicle.new_plate_number(plate_number)

  vehicle.new_vehicle(vehicle_id, plate, vehicle_type)
}

fn make_request(
  candidate_vehicle: vehicle.Vehicle,
) -> entry_parking.EntryParkingRequest {
  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(ticket_id) = parking_ticket.new_parking_ticket_id("TICKET-001")

  entry_parking.EntryParkingRequest(
    session_id: session_id,
    ticket_id: ticket_id,
    vehicle: candidate_vehicle,
    entry_time: 1000,
  )
}

fn make_car() -> vehicle.Vehicle {
  make_vehicle("VEHICLE-001", "B 1234 ABC", vehicle.Car)
}

fn close_database(db: sqlight.Connection) {
  let assert Ok(Nil) = sqlight.close(db)
}

// MARK: Successful Entry

pub fn successful_entry_persists_vehicle_session_and_ticket_test() {
  let db = setup_database(True)
  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request(make_car())

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Ok(entry_result) -> {
      should.equal(
        parking_session.get_parking_session_id_value(
          parking_session.get_parking_session_id(entry_result.session),
        ),
        "SESSION-001",
      )

      should.equal(
        parking_ticket.get_parking_ticket_id_value(
          parking_ticket.get_parking_ticket_id(entry_result.ticket),
        ),
        "TICKET-001",
      )

      should.equal(
        parking_slot.get_parking_slot_id_value(parking_slot.get_parking_slot_id(
          entry_result.slot,
        )),
        "SLOT-001",
      )
    }

    Error(_) -> should.fail()
  }

  count_rows(db, "vehicles")
  |> should.equal(1)

  count_rows(db, "parking_sessions")
  |> should.equal(1)

  count_rows(db, "parking_tickets")
  |> should.equal(1)

  get_session_state(db)
  |> should.equal("Active")

  close_database(db)
}

// MARK: Existing Vehicle

pub fn existing_vehicle_is_not_duplicated_test() {
  let db = setup_database(True)

  let _ =
    execute(
      db,
      "
      INSERT INTO vehicles (id, plate_number, vehicle_type)
      VALUES ('VEHICLE-001', 'B 1234 ABC', 'Car');
      ",
    )

  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request(make_car())

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }

  count_rows(db, "vehicles")
  |> should.equal(1)

  count_rows(db, "parking_sessions")
  |> should.equal(1)

  count_rows(db, "parking_tickets")
  |> should.equal(1)

  close_database(db)
}

// MARK: Vehicle Identity Conflict

pub fn vehicle_identity_conflict_rejects_entry_test() {
  let db = setup_database(True)

  let _ =
    execute(
      db,
      "
      INSERT INTO vehicles (id, plate_number, vehicle_type)
      VALUES ('VEHICLE-001', 'B 1234 ABC', 'Car');
      ",
    )

  let transaction = sqlite_entry_parking_transaction.new(db)

  let conflicting_vehicle =
    make_vehicle("VEHICLE-001", "B 9999 XYZ", vehicle.Car)

  let request = make_request(conflicting_vehicle)

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  count_rows(db, "vehicles")
  |> should.equal(1)

  count_rows(db, "parking_sessions")
  |> should.equal(0)

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}

// MARK: No Available Slot

pub fn no_available_slot_rolls_back_vehicle_test() {
  let db = setup_database(False)
  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request(make_car())

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.EntryFailed(
      entry_parking.NoAvailableParkingSlot,
    )) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // Vehicle persistence happens before slot allocation.
  // The failed use case must roll back that INSERT.
  count_rows(db, "vehicles")
  |> should.equal(0)

  count_rows(db, "parking_sessions")
  |> should.equal(0)

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}

// MARK: Session Persistence Failure

pub fn failed_session_insert_rolls_back_vehicle_test() {
  let db = setup_database(True)

  let _ =
    execute(
      db,
      "
      CREATE TRIGGER reject_session_insert
      BEFORE INSERT ON parking_sessions
      BEGIN
        SELECT RAISE(ABORT, 'Simulated session insert failure');
      END;
      ",
    )

  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request(make_car())

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // Vehicle INSERT must be rolled back.
  count_rows(db, "vehicles")
  |> should.equal(0)

  count_rows(db, "parking_sessions")
  |> should.equal(0)

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}

// MARK: Ticket Persistence Failure

pub fn failed_ticket_insert_rolls_back_vehicle_and_session_test() {
  let db = setup_database(True)

  let _ =
    execute(
      db,
      "
      CREATE TRIGGER reject_ticket_insert
      BEFORE INSERT ON parking_tickets
      BEGIN
        SELECT RAISE(ABORT, 'Simulated ticket insert failure');
      END;
      ",
    )

  let transaction = sqlite_entry_parking_transaction.new(db)
  let request = make_request(make_car())

  let result = sqlite_entry_parking_transaction.enter(transaction, request)

  case result {
    Error(entry_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // Both earlier INSERT operations must be rolled back.
  count_rows(db, "vehicles")
  |> should.equal(0)

  count_rows(db, "parking_sessions")
  |> should.equal(0)

  count_rows(db, "parking_tickets")
  |> should.equal(0)

  close_database(db)
}
