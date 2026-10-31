import domain/vehicle
import gleeunit/should

// MARK: Vehicle ID

pub fn vehicle_id_rejects_empty_string_test() {
  vehicle.new_vehicle_id("")
  |> should.equal(Error(vehicle.EmptyVehicleId))
}

pub fn vehicle_id_rejects_whitespace_only_test() {
  vehicle.new_vehicle_id("   ")
  |> should.equal(Error(vehicle.EmptyVehicleId))
}

pub fn vehicle_id_trims_whitespace_test() {
  let result = vehicle.new_vehicle_id(" V001 ")

  case result {
    Ok(id) ->
      vehicle.get_vehicle_id_value(id)
      |> should.equal("V001")

    Error(_) -> should.fail()
  }
}

// MARK: Plate Number

pub fn plate_number_rejects_empty_string_test() {
  vehicle.new_plate_number("")
  |> should.equal(Error(vehicle.EmptyPlateNumber))
}

pub fn plate_number_rejects_whitespace_only_test() {
  vehicle.new_plate_number("   ")
  |> should.equal(Error(vehicle.EmptyPlateNumber))
}

pub fn plate_number_trims_whitespace_test() {
  let result = vehicle.new_plate_number(" B 1234 ABC ")

  case result {
    Ok(plate) ->
      vehicle.get_plate_number_value(plate)
      |> should.equal("B 1234 ABC")

    Error(_) -> should.fail()
  }
}

// MARK: Vehicle

pub fn vehicle_stores_its_attributes_test() {
  let assert Ok(id) = vehicle.new_vehicle_id("V001")
  let assert Ok(plate) = vehicle.new_plate_number("B 1234 ABC")

  let registered_vehicle = vehicle.new_vehicle(id, plate, vehicle.Car)

  vehicle.get_vehicle_id(registered_vehicle)
  |> vehicle.get_vehicle_id_value
  |> should.equal("V001")

  vehicle.get_vehicle_plate_number(registered_vehicle)
  |> vehicle.get_plate_number_value
  |> should.equal("B 1234 ABC")

  vehicle.get_vehicle_type(registered_vehicle)
  |> should.equal(vehicle.Car)
}
