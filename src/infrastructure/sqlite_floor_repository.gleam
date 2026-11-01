import application/ports/parking_floor_repository
import application/ports/repository_error
import domain/floor
import domain/parking_slot
import domain/vehicle
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import sqlight

pub type SqliteFloorRepository {
  SqliteFloorRepository(db: sqlight.Connection)
}

pub fn new(db: sqlight.Connection) -> SqliteFloorRepository {
  SqliteFloorRepository(db: db)
}

// -----------------------------------------------------------------------------
// Transaction
// -----------------------------------------------------------------------------

fn begin_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  query(sqlight.exec("BEGIN IMMEDIATE", on: db))
}

fn commit_transaction(
  db: sqlight.Connection,
) -> Result(Nil, repository_error.RepositoryError) {
  query(sqlight.exec("COMMIT", on: db))
}

fn rollback_transaction(db: sqlight.Connection) -> Nil {
  let _ = sqlight.exec("ROLLBACK", on: db)
  Nil
}

// -----------------------------------------------------------------------------
// Repository write operations
// -----------------------------------------------------------------------------

fn save_floor(
  repository: SqliteFloorRepository,
  parking_floor: floor.ParkingFloor,
) -> Result(Nil, repository_error.RepositoryError) {
  let SqliteFloorRepository(db) = repository

  use _ <- result.try(begin_transaction(db))

  case save_floor_data(db, parking_floor) {
    Ok(Nil) ->
      case commit_transaction(db) {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> {
          rollback_transaction(db)
          Error(error)
        }
      }

    Error(error) -> {
      rollback_transaction(db)
      Error(error)
    }
  }
}

fn save_floor_data(
  db: sqlight.Connection,
  parking_floor: floor.ParkingFloor,
) -> Result(Nil, repository_error.RepositoryError) {
  use _ <- result.try(insert_floor_if_missing(db, parking_floor))

  save_slots(db, parking_floor, floor.get_parking_floor_slots(parking_floor))
}

fn insert_floor_if_missing(
  db: sqlight.Connection,
  parking_floor: floor.ParkingFloor,
) -> Result(Nil, repository_error.RepositoryError) {
  let floor_id =
    parking_floor
    |> floor.get_parking_floor_id
    |> floor.get_parking_floor_id_value

  let sql =
    "INSERT INTO parking_floors (id) VALUES ('"
    <> escape_sql(floor_id)
    <> "') ON CONFLICT(id) DO NOTHING;"

  query(sqlight.exec(sql, on: db))
}

fn save_slots(
  db: sqlight.Connection,
  parking_floor: floor.ParkingFloor,
  slots: List(parking_slot.ParkingSlot),
) -> Result(Nil, repository_error.RepositoryError) {
  let floor_id =
    parking_floor
    |> floor.get_parking_floor_id
    |> floor.get_parking_floor_id_value

  list.fold(slots, Ok(Nil), fn(acc, slot) {
    use _ <- result.try(acc)
    save_slot(db, floor_id, slot)
  })
}

fn save_slot(
  db: sqlight.Connection,
  floor_id: String,
  slot: parking_slot.ParkingSlot,
) -> Result(Nil, repository_error.RepositoryError) {
  let slot_id =
    slot
    |> parking_slot.get_parking_slot_id
    |> parking_slot.get_parking_slot_id_value

  let vehicle_type =
    slot
    |> parking_slot.get_supported_vehicle_type
    |> vehicle_type_to_string

  let sql =
    "INSERT INTO parking_slots "
    <> "(id, floor_id, supported_vehicle_type) VALUES ('"
    <> escape_sql(slot_id)
    <> "', '"
    <> escape_sql(floor_id)
    <> "', '"
    <> vehicle_type
    <> "') ON CONFLICT(id) DO NOTHING;"

  use _ <- result.try(query(sqlight.exec(sql, on: db)))

  verify_slot_configuration(db, floor_id, slot_id, vehicle_type)
}

fn verify_slot_configuration(
  db: sqlight.Connection,
  expected_floor_id: String,
  slot_id: String,
  expected_vehicle_type: String,
) -> Result(Nil, repository_error.RepositoryError) {
  let sql =
    "SELECT floor_id, supported_vehicle_type "
    <> "FROM parking_slots WHERE id = '"
    <> escape_sql(slot_id)
    <> "';"

  use rows <- result.try(
    query(sqlight.query(
      sql,
      on: db,
      with: [],
      expecting: slot_configuration_decoder(),
    )),
  )

  case rows {
    [#(actual_floor_id, actual_vehicle_type)] ->
      case
        actual_floor_id == expected_floor_id
        && actual_vehicle_type == expected_vehicle_type
      {
        True -> Ok(Nil)

        False ->
          Error(repository_error.StorageError(
            "Parking slot configuration conflict: " <> slot_id,
          ))
      }

    _ ->
      Error(repository_error.StorageError(
        "Unable to verify parking slot: " <> slot_id,
      ))
  }
}

fn slot_configuration_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(floor_id) {
    decode.at([1], decode.string)
    |> decode.map(fn(vehicle_type) { #(floor_id, vehicle_type) })
  })
}

fn vehicle_type_to_string(value: vehicle.VehicleType) -> String {
  case value {
    vehicle.Motorcycle -> "Motorcycle"
    vehicle.Car -> "Car"
    vehicle.Truck -> "Truck"
  }
}

// -----------------------------------------------------------------------------
// SQL helpers
// -----------------------------------------------------------------------------

fn escape_sql(value: String) -> String {
  string.replace(value, "'", "''")
}

// -----------------------------------------------------------------------------
// Port adapter
// -----------------------------------------------------------------------------

pub fn to_port(
  repository: SqliteFloorRepository,
) -> parking_floor_repository.ParkingFloorRepository {
  parking_floor_repository.ParkingFloorRepository(
    get_all_floors: fn() { get_all_floors(repository) },
    save_floor: fn(parking_floor) { save_floor(repository, parking_floor) },
  )
}

// -----------------------------------------------------------------------------
// Repository read operations
// -----------------------------------------------------------------------------

pub fn get_all_floors(
  repository: SqliteFloorRepository,
) -> Result(List(floor.ParkingFloor), repository_error.RepositoryError) {
  let SqliteFloorRepository(db: db) = repository

  use floor_ids <- result.try(load_floor_ids(db))
  use floors <- result.try(build_floors(floor_ids))
  use slots <- result.try(load_slot_data(db))

  attach_slots(floors, slots)
}

// -----------------------------------------------------------------------------
// Database queries
// -----------------------------------------------------------------------------

fn load_floor_ids(
  db: sqlight.Connection,
) -> Result(List(String), repository_error.RepositoryError) {
  query(sqlight.query(
    "
    SELECT id
    FROM parking_floors
    ORDER BY id;
    ",
    on: db,
    with: [],
    expecting: decode.at([0], decode.string),
  ))
}

fn load_slot_data(
  db: sqlight.Connection,
) -> Result(List(#(String, String, String)), repository_error.RepositoryError) {
  query(sqlight.query(
    "
    SELECT floor_id, id, supported_vehicle_type
    FROM parking_slots
    ORDER BY floor_id, id;
    ",
    on: db,
    with: [],
    expecting: slot_decoder(),
  ))
}

fn slot_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(floor_id) {
    decode.at([1], decode.string)
    |> decode.then(fn(slot_id) {
      decode.at([2], decode.string)
      |> decode.map(fn(vehicle_type) { #(floor_id, slot_id, vehicle_type) })
    })
  })
}

// -----------------------------------------------------------------------------
// Database -> Domain conversion
// -----------------------------------------------------------------------------

fn build_floors(
  ids: List(String),
) -> Result(List(floor.ParkingFloor), repository_error.RepositoryError) {
  list.fold(ids, Ok([]), fn(acc, id) {
    use floors <- result.try(acc)

    use floor_id <- result.try(case floor.new_parking_floor_id(id) {
      Ok(value) -> Ok(value)
      Error(error) ->
        Error(repository_error.StorageError(floor.error_message(error)))
    })

    Ok(list.append(floors, [floor.new_parking_floor(floor_id)]))
  })
}

fn build_slot(
  id: String,
  vehicle_type: String,
) -> Result(parking_slot.ParkingSlot, repository_error.RepositoryError) {
  use slot_id <- result.try(case parking_slot.new_parking_slot_id(id) {
    Ok(value) -> Ok(value)
    Error(error) ->
      Error(repository_error.StorageError(parking_slot.error_message(error)))
  })

  use supported_vehicle_type <- result.try(parse_vehicle_type(vehicle_type))

  Ok(parking_slot.new_parking_slot(slot_id, supported_vehicle_type))
}

fn parse_vehicle_type(
  value: String,
) -> Result(vehicle.VehicleType, repository_error.RepositoryError) {
  case value {
    "Motorcycle" -> Ok(vehicle.Motorcycle)
    "Car" -> Ok(vehicle.Car)
    "Truck" -> Ok(vehicle.Truck)
    _ ->
      Error(repository_error.StorageError(
        "Unknown supported vehicle type: " <> value,
      ))
  }
}

// -----------------------------------------------------------------------------
// Domain aggregation
// -----------------------------------------------------------------------------

fn attach_slots(
  floors: List(floor.ParkingFloor),
  slots: List(#(String, String, String)),
) -> Result(List(floor.ParkingFloor), repository_error.RepositoryError) {
  list.fold(slots, Ok(floors), fn(acc, slot_data) {
    use current_floors <- result.try(acc)

    let #(floor_id, slot_id, vehicle_type) = slot_data

    use slot <- result.try(build_slot(slot_id, vehicle_type))

    add_slot_to_floors(current_floors, floor_id, slot)
  })
}

fn floor_id_value(current_floor: floor.ParkingFloor) -> String {
  current_floor
  |> floor.get_parking_floor_id
  |> floor.get_parking_floor_id_value
}

fn add_slot_to_floors(
  floors: List(floor.ParkingFloor),
  floor_id: String,
  slot: parking_slot.ParkingSlot,
) -> Result(List(floor.ParkingFloor), repository_error.RepositoryError) {
  let floor_exists =
    list.any(floors, fn(current_floor) {
      floor_id_value(current_floor) == floor_id
    })

  case floor_exists {
    False ->
      Error(repository_error.StorageError(
        "Parking slot references an unknown floor: " <> floor_id,
      ))

    True ->
      floors
      |> list.map(fn(current_floor) {
        add_slot_to_matching_floor(current_floor, floor_id, slot)
      })
      |> result.all
  }
}

fn add_slot_to_matching_floor(
  current_floor: floor.ParkingFloor,
  target_floor_id: String,
  slot: parking_slot.ParkingSlot,
) -> Result(floor.ParkingFloor, repository_error.RepositoryError) {
  case floor_id_value(current_floor) == target_floor_id {
    True ->
      floor.add_parking_slot(current_floor, slot)
      |> result.map_error(fn(error) {
        repository_error.StorageError(floor.error_message(error))
      })

    False -> Ok(current_floor)
  }
}

// -----------------------------------------------------------------------------
// Error mapping
// -----------------------------------------------------------------------------

fn query(
  result: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case result {
    Ok(value) -> Ok(value)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.StorageError(message))
  }
}
