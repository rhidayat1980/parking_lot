import domain/floor
import domain/parking_slot
import domain/vehicle
import gleam/list
import gleeunit/should
import infrastructure/sqlite_connection
import infrastructure/sqlite_floor_repository
import sqlight

fn setup_database() -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(Nil) =
    sqlight.exec(
      "
    CREATE TABLE parking_floors (
      id TEXT PRIMARY KEY NOT NULL
    );

    CREATE TABLE parking_slots (
      id TEXT PRIMARY KEY NOT NULL,
      floor_id TEXT NOT NULL,
      supported_vehicle_type TEXT NOT NULL,
      FOREIGN KEY (floor_id) REFERENCES parking_floors(id),
      UNIQUE (floor_id, id)
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

fn floor_ids(floors: List(floor.ParkingFloor)) -> List(String) {
  list.map(floors, fn(current_floor) {
    current_floor
    |> floor.get_parking_floor_id
    |> floor.get_parking_floor_id_value
  })
}

pub fn get_all_floors_empty_database_test() {
  let db = setup_database()
  let repository = sqlite_floor_repository.new(db)

  sqlite_floor_repository.get_all_floors(repository)
  |> should.equal(Ok([]))

  let assert Ok(Nil) = sqlight.close(db)
}

pub fn get_all_floors_without_slots_test() {
  let db = setup_database()

  execute(
    db,
    "
    INSERT INTO parking_floors (id)
    VALUES ('FLOOR-01'), ('FLOOR-02'), ('FLOOR-03');
    ",
  )

  let repository = sqlite_floor_repository.new(db)

  let assert Ok(floors) = sqlite_floor_repository.get_all_floors(repository)

  floor_ids(floors)
  |> should.equal(["FLOOR-01", "FLOOR-02", "FLOOR-03"])

  list.map(floors, floor.get_parking_floor_slot_count)
  |> should.equal([0, 0, 0])

  let assert Ok(Nil) = sqlight.close(db)
}

pub fn get_all_floors_with_slots_test() {
  let db = setup_database()

  execute(
    db,
    "
    INSERT INTO parking_floors (id)
    VALUES ('FLOOR-01'), ('FLOOR-02'), ('FLOOR-03');

    INSERT INTO parking_slots (id, floor_id, supported_vehicle_type)
    VALUES
      ('SLOT-01', 'FLOOR-01', 'Motorcycle'),
      ('SLOT-02', 'FLOOR-01', 'Car'),
      ('SLOT-03', 'FLOOR-02', 'Truck');
    ",
  )

  let repository = sqlite_floor_repository.new(db)

  let assert Ok(floors) = sqlite_floor_repository.get_all_floors(repository)

  floor_ids(floors)
  |> should.equal(["FLOOR-01", "FLOOR-02", "FLOOR-03"])

  list.map(floors, floor.get_parking_floor_slot_count)
  |> should.equal([2, 1, 0])

  let assert [first_floor, second_floor, third_floor] = floors

  first_floor
  |> floor.get_parking_floor_slots
  |> list.map(parking_slot.get_supported_vehicle_type)
  |> should.equal([vehicle.Motorcycle, vehicle.Car])

  second_floor
  |> floor.get_parking_floor_slots
  |> list.map(parking_slot.get_supported_vehicle_type)
  |> should.equal([vehicle.Truck])

  third_floor
  |> floor.get_parking_floor_slots
  |> should.equal([])

  let assert Ok(Nil) = sqlight.close(db)
}
