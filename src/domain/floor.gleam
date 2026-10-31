import domain/parking_slot
import gleam/list
import gleam/string

// MARK: Errors

pub type ParkingFloorError {
  EmptyParkingFloorId
  ParkingSlotAlreadyOnFloor
}

pub fn error_message(error: ParkingFloorError) -> String {
  case error {
    EmptyParkingFloorId -> "Parking floor ID cannot be empty"

    ParkingSlotAlreadyOnFloor -> "Parking slot already exists on this floor"
  }
}

// MARK: Parking Floor ID

pub opaque type ParkingFloorId {
  ParkingFloorId(String)
}

pub fn new_parking_floor_id(
  value: String,
) -> Result(ParkingFloorId, ParkingFloorError) {
  let trimmed = string.trim(value)

  case trimmed {
    "" -> Error(EmptyParkingFloorId)
    _ -> Ok(ParkingFloorId(trimmed))
  }
}

pub fn get_parking_floor_id_value(id: ParkingFloorId) -> String {
  let ParkingFloorId(value) = id
  value
}

// MARK: Parking Floor

pub opaque type ParkingFloor {
  ParkingFloor(id: ParkingFloorId, slots: List(parking_slot.ParkingSlot))
}

pub fn new_parking_floor(id: ParkingFloorId) -> ParkingFloor {
  ParkingFloor(id: id, slots: [])
}

// MARK: Accessors

pub fn get_parking_floor_id(floor: ParkingFloor) -> ParkingFloorId {
  let ParkingFloor(id: id, ..) = floor
  id
}

pub fn get_parking_floor_slots(
  floor: ParkingFloor,
) -> List(parking_slot.ParkingSlot) {
  let ParkingFloor(slots: slots, ..) = floor
  slots
}

pub fn get_parking_floor_slot_count(floor: ParkingFloor) -> Int {
  list.length(get_parking_floor_slots(floor))
}

// MARK: Add Slot

pub fn add_parking_slot(
  floor: ParkingFloor,
  slot: parking_slot.ParkingSlot,
) -> Result(ParkingFloor, ParkingFloorError) {
  let slots = get_parking_floor_slots(floor)
  let slot_id = parking_slot.get_parking_slot_id(slot)

  let already_exists =
    list.any(slots, fn(existing_slot) {
      parking_slot.get_parking_slot_id(existing_slot) == slot_id
    })

  case already_exists {
    True -> Error(ParkingSlotAlreadyOnFloor)

    False -> Ok(ParkingFloor(..floor, slots: list.append(slots, [slot])))
  }
}
