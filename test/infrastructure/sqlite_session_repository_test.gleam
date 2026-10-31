import domain/parking_session
import domain/parking_slot
import domain/vehicle
import gleam/list
import gleam/option.{None}
import gleeunit/should
import infrastructure/sqlite_connection
import infrastructure/sqlite_session_repository
import sqlight

fn setup_database() -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(Nil) =
    sqlight.exec(
      "
    CREATE TABLE parking_sessions (
      id TEXT PRIMARY KEY NOT NULL,
      vehicle_id TEXT NOT NULL,
      slot_id TEXT NOT NULL,
      entry_time INTEGER NOT NULL,
      exit_time INTEGER,
      state TEXT NOT NULL
    );
    ",
      on: db,
    )

  db
}

fn execute(db: sqlight.Connection, sql: String) -> Nil {
  let assert Ok(Nil) = sqlight.exec(sql, on: db)
  Nil
}

pub fn get_active_sessions_empty_database_test() {
  let db = setup_database()
  let repository = sqlite_session_repository.new(db)

  sqlite_session_repository.get_active_sessions(repository)
  |> should.equal(Ok([]))

  let assert Ok(Nil) = sqlight.close(db)
}

pub fn get_active_sessions_only_returns_active_test() {
  let db = setup_database()

  execute(
    db,
    "
    INSERT INTO parking_sessions
      (id, vehicle_id, slot_id, entry_time, exit_time, state)
    VALUES
      ('SESSION-01', 'VEHICLE-01', 'SLOT-01', 1000, NULL, 'Active'),
      ('SESSION-02', 'VEHICLE-02', 'SLOT-02', 2000, 3000, 'Closed'),
      ('SESSION-03', 'VEHICLE-03', 'SLOT-03', 1500, NULL, 'Active');
    ",
  )

  let repository = sqlite_session_repository.new(db)

  let assert Ok(sessions) =
    sqlite_session_repository.get_active_sessions(repository)

  list.length(sessions)
  |> should.equal(2)

  let assert [first_session, second_session] = sessions

  first_session
  |> parking_session.get_parking_session_id
  |> parking_session.get_parking_session_id_value
  |> should.equal("SESSION-01")

  second_session
  |> parking_session.get_parking_session_id
  |> parking_session.get_parking_session_id_value
  |> should.equal("SESSION-03")

  let assert parking_session.Active =
    parking_session.get_parking_session_state(first_session)

  let assert parking_session.Active =
    parking_session.get_parking_session_state(second_session)

  let assert Ok(Nil) = sqlight.close(db)
}

pub fn get_active_sessions_maps_domain_fields_test() {
  let db = setup_database()

  execute(
    db,
    "
    INSERT INTO parking_sessions
      (id, vehicle_id, slot_id, entry_time, exit_time, state)
    VALUES
      ('SESSION-01', 'VEHICLE-01', 'SLOT-01', 12345, NULL, 'Active');
    ",
  )

  let repository = sqlite_session_repository.new(db)

  let assert Ok([session]) =
    sqlite_session_repository.get_active_sessions(repository)

  parking_session.get_parking_session_id(session)
  |> parking_session.get_parking_session_id_value
  |> should.equal("SESSION-01")

  parking_session.get_parking_session_vehicle_id(session)
  |> vehicle.get_vehicle_id_value
  |> should.equal("VEHICLE-01")

  parking_session.get_parking_session_slot_id(session)
  |> parking_slot.get_parking_slot_id_value
  |> should.equal("SLOT-01")

  parking_session.get_parking_session_entry_time(session)
  |> should.equal(12_345)

  parking_session.get_parking_session_state(session)
  |> should.equal(parking_session.Active)

  parking_session.get_parking_session_exit_time(session)
  |> should.equal(None)

  let assert Ok(Nil) = sqlight.close(db)
}
