import domain/parking_slot
import domain/vehicle
import gleeunit/should

// MARK: Parking Slot ID

pub fn parking_slot_id_rejects_empty_string_test() {
  parking_slot.new_parking_slot_id("")
  |> should.equal(Error(parking_slot.EmptyParkingSlotId))
}

pub fn parking_slot_id_rejects_whitespace_only_test() {
  parking_slot.new_parking_slot_id("   ")
  |> should.equal(Error(parking_slot.EmptyParkingSlotId))
}

pub fn parking_slot_id_trims_whitespace_test() {
  let result = parking_slot.new_parking_slot_id(" A-01 ")

  case result {
    Ok(id) ->
      parking_slot.get_parking_slot_id_value(id)
      |> should.equal("A-01")

    Error(_) -> should.fail()
  }
}

// MARK: Parking Slot

pub fn parking_slot_stores_its_attributes_test() {
  let assert Ok(id) = parking_slot.new_parking_slot_id("A-01")

  let slot = parking_slot.new_parking_slot(id, vehicle.Car)

  parking_slot.get_parking_slot_id(slot)
  |> parking_slot.get_parking_slot_id_value
  |> should.equal("A-01")

  parking_slot.get_supported_vehicle_type(slot)
  |> should.equal(vehicle.Car)
}

// MARK: Vehicle Compatibility

pub fn parking_slot_checks_vehicle_compatibility_test() {
  let assert Ok(slot_id) = parking_slot.new_parking_slot_id("A-01")
  let slot = parking_slot.new_parking_slot(slot_id, vehicle.Car)

  let assert Ok(car_id) = vehicle.new_vehicle_id("V001")
  let assert Ok(car_plate) = vehicle.new_plate_number("B 1234 ABC")
  let car = vehicle.new_vehicle(car_id, car_plate, vehicle.Car)

  let assert Ok(motorcycle_id) = vehicle.new_vehicle_id("V002")
  let assert Ok(motorcycle_plate) = vehicle.new_plate_number("B 5678 XYZ")

  let motorcycle =
    vehicle.new_vehicle(motorcycle_id, motorcycle_plate, vehicle.Motorcycle)

  parking_slot.supports_vehicle(slot, car)
  |> should.equal(True)

  parking_slot.supports_vehicle(slot, motorcycle)
  |> should.equal(False)
}
