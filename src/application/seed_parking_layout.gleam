import application/ports/parking_floor_repository
import application/ports/repository_error
import domain/floor
import domain/parking_slot
import domain/vehicle
import gleam/list
import gleam/result

pub type SeedParkingLayoutError {
  InvalidFloorId(floor.ParkingFloorError)
  InvalidSlotId(parking_slot.ParkingSlotError)
  FloorConfigurationFailed(floor.ParkingFloorError)
  RepositoryFailed(repository_error.RepositoryError)
}

pub fn seed(
  repository: parking_floor_repository.ParkingFloorRepository,
) -> Result(Nil, SeedParkingLayoutError) {
  let parking_floor_repository.ParkingFloorRepository(
    save_floor: save_floor,
    ..,
  ) = repository

  use first_floor <- result.try(
    build_floor("F1", [
      #("M-01", vehicle.Motorcycle),
      #("M-02", vehicle.Motorcycle),
      #("C-01", vehicle.Car),
      #("C-02", vehicle.Car),
      #("T-01", vehicle.Truck),
    ]),
  )

  use _ <- result.try(
    save_floor(first_floor)
    |> result.map_error(RepositoryFailed),
  )

  use second_floor <- result.try(
    build_floor("F2", [
      #("M-03", vehicle.Motorcycle),
      #("C-03", vehicle.Car),
      #("C-04", vehicle.Car),
    ]),
  )

  save_floor(second_floor)
  |> result.map_error(RepositoryFailed)
}

fn build_floor(
  floor_id_value: String,
  slot_definitions: List(#(String, vehicle.VehicleType)),
) -> Result(floor.ParkingFloor, SeedParkingLayoutError) {
  use floor_id <- result.try(
    floor.new_parking_floor_id(floor_id_value)
    |> result.map_error(InvalidFloorId),
  )

  let initial_floor = floor.new_parking_floor(floor_id)

  list.fold(slot_definitions, Ok(initial_floor), fn(acc, definition) {
    use current_floor <- result.try(acc)

    let #(slot_id_value, supported_vehicle_type) = definition

    use slot_id <- result.try(
      parking_slot.new_parking_slot_id(slot_id_value)
      |> result.map_error(InvalidSlotId),
    )

    let slot = parking_slot.new_parking_slot(slot_id, supported_vehicle_type)

    floor.add_parking_slot(current_floor, slot)
    |> result.map_error(FloorConfigurationFailed)
  })
}
