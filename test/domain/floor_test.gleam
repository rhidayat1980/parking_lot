import domain/floor
import domain/parking_slot
import domain/vehicle
import gleeunit/should

// MARK: Test Helpers

fn make_floor() -> floor.ParkingFloor {
  let assert Ok(floor_id) = floor.new_parking_floor_id("FLOOR-01")
  floor.new_parking_floor(floor_id)
}

fn make_slot(id: String) -> parking_slot.ParkingSlot {
  let assert Ok(slot_id) = parking_slot.new_parking_slot_id(id)
  parking_slot.new_parking_slot(slot_id, vehicle.Car)
}

// MARK: Parking Floor ID

pub fn floor_id_rejects_empty_value_test() {
  should.equal(floor.new_parking_floor_id(""), Error(floor.EmptyParkingFloorId))
}

pub fn floor_id_rejects_whitespace_test() {
  should.equal(
    floor.new_parking_floor_id("   "),
    Error(floor.EmptyParkingFloorId),
  )
}

pub fn floor_id_trims_whitespace_test() {
  let assert Ok(id) = floor.new_parking_floor_id("  FLOOR-01  ")

  should.equal(floor.get_parking_floor_id_value(id), "FLOOR-01")
}

// MARK: Parking Floor

pub fn new_floor_starts_without_slots_test() {
  let new_floor = make_floor()

  should.equal(floor.get_parking_floor_slot_count(new_floor), 0)
}

pub fn floor_exposes_its_id_test() {
  let new_floor = make_floor()

  floor.get_parking_floor_id(new_floor)
  |> floor.get_parking_floor_id_value
  |> should.equal("FLOOR-01")
}

pub fn floor_can_add_a_slot_test() {
  let new_floor = make_floor()
  let slot = make_slot("SLOT-01")

  let assert Ok(updated_floor) = floor.add_parking_slot(new_floor, slot)

  should.equal(floor.get_parking_floor_slot_count(updated_floor), 1)
}

pub fn floor_can_add_multiple_slots_test() {
  let new_floor = make_floor()
  let first_slot = make_slot("SLOT-01")
  let second_slot = make_slot("SLOT-02")

  let assert Ok(floor_with_first_slot) =
    floor.add_parking_slot(new_floor, first_slot)

  let assert Ok(floor_with_two_slots) =
    floor.add_parking_slot(floor_with_first_slot, second_slot)

  should.equal(floor.get_parking_floor_slot_count(floor_with_two_slots), 2)
}

pub fn floor_rejects_duplicate_slot_id_test() {
  let new_floor = make_floor()
  let first_slot = make_slot("SLOT-01")
  let duplicate_slot = make_slot("SLOT-01")

  let assert Ok(floor_with_slot) = floor.add_parking_slot(new_floor, first_slot)

  should.equal(
    floor.add_parking_slot(floor_with_slot, duplicate_slot),
    Error(floor.ParkingSlotAlreadyOnFloor),
  )
}

// MARK: Immutability

pub fn failed_add_does_not_change_original_floor_test() {
  let new_floor = make_floor()
  let slot = make_slot("SLOT-01")

  let assert Ok(updated_floor) = floor.add_parking_slot(new_floor, slot)

  should.equal(floor.get_parking_floor_slot_count(new_floor), 0)
  should.equal(floor.get_parking_floor_slot_count(updated_floor), 1)
}

pub fn successful_add_does_not_change_original_floor_test() {
  let original_floor = make_floor()
  let slot = make_slot("SLOT-01")

  let assert Ok(updated_floor) = floor.add_parking_slot(original_floor, slot)

  should.equal(floor.get_parking_floor_slot_count(original_floor), 0)
  should.equal(floor.get_parking_floor_slot_count(updated_floor), 1)
}
