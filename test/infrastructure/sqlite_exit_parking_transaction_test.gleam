import application/exit_parking
import application/ports/exit_parking_transaction
import application/ports/repository_error
import domain/parking_session
import domain/payment
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import gleeunit/should
import infrastructure/sqlite_connection
import infrastructure/sqlite_exit_parking_transaction
import simplifile
import sqlight

// MARK: Test Helpers

fn setup_database() -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(initial_migration) =
    simplifile.read(
      from: "priv/repo/migrations/001_create_parking_schema.up.sql",
    )

  let assert Ok(Nil) = sqlight.exec(initial_migration, on: db)

  let assert Ok(payment_migration) =
    simplifile.read(from: "priv/repo/migrations/002_create_payments.up.sql")

  let assert Ok(Nil) = sqlight.exec(payment_migration, on: db)

  let assert Ok(Nil) =
    sqlight.exec(
      "
      INSERT INTO vehicles (id, plate_number, vehicle_type)
      VALUES ('VEHICLE-001', 'B 1234 ABC', 'Car');

      INSERT INTO parking_floors (id)
      VALUES ('FLOOR-001');

      INSERT INTO parking_slots (id, floor_id, supported_vehicle_type)
      VALUES ('SLOT-001', 'FLOOR-001', 'Car');

      INSERT INTO parking_sessions
        (id, vehicle_id, slot_id, entry_time, exit_time, state)
      VALUES
        ('SESSION-001', 'VEHICLE-001', 'SLOT-001', 1000, NULL, 'Active');
      ",
      on: db,
    )

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

fn get_payment_status(db: sqlight.Connection) -> String {
  let assert Ok([status]) =
    sqlight.query(
      "SELECT status FROM payments WHERE id = 'PAYMENT-001';",
      on: db,
      with: [],
      expecting: decode.field(0, decode.string, fn(value) {
        decode.success(value)
      }),
    )

  status
}

fn make_request(
  payment_id: Option(payment.PaymentId),
  exit_time: Int,
  hourly_rate: Int,
) -> exit_parking.ExitParkingRequest {
  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  exit_parking.ExitParkingRequest(
    session_id: session_id,
    payment_id: payment_id,
    exit_time: exit_time,
    hourly_rate: hourly_rate,
    payment_method: payment.Cash,
  )
}

fn make_payment_id() -> payment.PaymentId {
  let assert Ok(id) = payment.new_payment_id("PAYMENT-001")
  id
}

fn close_database(db: sqlight.Connection) {
  let assert Ok(Nil) = sqlight.close(db)
}

// MARK: Successful Transaction

pub fn successful_exit_persists_payment_and_closed_session_test() {
  let db = setup_database()
  let transaction = sqlite_exit_parking_transaction.new(db)

  let request = make_request(Some(make_payment_id()), 4600, 5000)

  let result = sqlite_exit_parking_transaction.exit(transaction, request)

  case result {
    Ok(exit_result) -> {
      should.equal(exit_result.fee, 5000)
      should.equal(exit_result.duration_seconds, 3600)

      should.equal(
        parking_session.get_parking_session_state(exit_result.session),
        parking_session.Closed(4600),
      )

      case exit_result.payment {
        Some(saved_payment) ->
          should.equal(
            payment.get_payment_status(saved_payment),
            payment.Succeeded,
          )

        None -> should.fail()
      }
    }

    Error(_) -> should.fail()
  }

  count_rows(db, "payments")
  |> should.equal(1)

  get_payment_status(db)
  |> should.equal("Succeeded")

  get_session_state(db)
  |> should.equal("Closed")

  close_database(db)
}

// MARK: Zero Fee

pub fn zero_fee_exit_closes_session_without_payment_test() {
  let db = setup_database()
  let transaction = sqlite_exit_parking_transaction.new(db)

  let request = make_request(None, 1000, 5000)

  let result = sqlite_exit_parking_transaction.exit(transaction, request)

  case result {
    Ok(exit_result) -> {
      should.equal(exit_result.fee, 0)
      should.equal(exit_result.payment, None)

      should.equal(
        parking_session.get_parking_session_state(exit_result.session),
        parking_session.Closed(1000),
      )
    }

    Error(_) -> should.fail()
  }

  count_rows(db, "payments")
  |> should.equal(0)

  get_session_state(db)
  |> should.equal("Closed")

  close_database(db)
}

// MARK: Session Not Found

pub fn missing_session_returns_session_not_found_test() {
  let db = setup_database()
  let transaction = sqlite_exit_parking_transaction.new(db)

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-MISSING")

  let request =
    exit_parking.ExitParkingRequest(
      session_id: session_id,
      payment_id: Some(make_payment_id()),
      exit_time: 4600,
      hourly_rate: 5000,
      payment_method: payment.Cash,
    )

  let result = sqlite_exit_parking_transaction.exit(transaction, request)

  case result {
    Error(exit_parking_transaction.ExitFailed(exit_parking.SessionNotFound)) ->
      Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  count_rows(db, "payments")
  |> should.equal(0)

  get_session_state(db)
  |> should.equal("Active")

  close_database(db)
}

// MARK: Missing Payment ID

pub fn missing_payment_id_rolls_back_exit_test() {
  let db = setup_database()
  let transaction = sqlite_exit_parking_transaction.new(db)

  let request = make_request(None, 4600, 5000)

  let result = sqlite_exit_parking_transaction.exit(transaction, request)

  case result {
    Error(exit_parking_transaction.ExitFailed(exit_parking.MissingPaymentId)) ->
      Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  count_rows(db, "payments")
  |> should.equal(0)

  get_session_state(db)
  |> should.equal("Active")

  close_database(db)
}

// MARK: Already Closed Session

pub fn closed_session_cannot_exit_again_test() {
  let db = setup_database()

  let _ =
    execute(
      db,
      "
    UPDATE parking_sessions
    SET exit_time = 2000, state = 'Closed'
    WHERE id = 'SESSION-001';
    ",
    )

  let transaction = sqlite_exit_parking_transaction.new(db)
  let request = make_request(Some(make_payment_id()), 3000, 5000)

  let result = sqlite_exit_parking_transaction.exit(transaction, request)

  case result {
    Error(exit_parking_transaction.ExitFailed(exit_parking.SessionClosingFailed(
      parking_session.ParkingSessionAlreadyClosed,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  count_rows(db, "payments")
  |> should.equal(0)

  get_session_state(db)
  |> should.equal("Closed")

  close_database(db)
}

// MARK: Atomic Rollback

pub fn failed_session_update_rolls_back_payment_test() {
  let db = setup_database()

  // Payment persistence happens before session persistence.
  // This trigger forces the second operation to fail.
  let _ =
    execute(
      db,
      "
    CREATE TRIGGER reject_session_exit
    BEFORE UPDATE ON parking_sessions
    BEGIN
      SELECT RAISE(ABORT, 'Simulated session update failure');
    END;
    ",
    )

  let transaction = sqlite_exit_parking_transaction.new(db)
  let request = make_request(Some(make_payment_id()), 4600, 5000)

  let result = sqlite_exit_parking_transaction.exit(transaction, request)

  case result {
    Error(exit_parking_transaction.RepositoryFailed(repository_error.StorageError(
      _,
    ))) -> Nil

    Error(_) -> should.fail()
    Ok(_) -> should.fail()
  }

  // The payment INSERT must be rolled back as well.
  count_rows(db, "payments")
  |> should.equal(0)

  // The original session must remain active.
  get_session_state(db)
  |> should.equal("Active")

  close_database(db)
}
