import gleam/string

// MARK: Errors

pub type VehicleError {
  EmptyVehicleId
  EmptyPlateNumber
}

pub fn error_message(error: VehicleError) -> String {
  case error {
    EmptyVehicleId -> "Vehicle ID cannot be empty"
    EmptyPlateNumber -> "Plate number cannot be empty"
  }
}

// MARK: Vehicle ID

pub opaque type VehicleId {
  VehicleId(String)
}

// A VehicleId is valid if its trimmed value is not empty.
pub fn new_vehicle_id(value: String) -> Result(VehicleId, VehicleError) {
  let trimmed = string.trim(value)

  case trimmed {
    "" -> Error(EmptyVehicleId)
    _ -> Ok(VehicleId(trimmed))
  }
}

// Returns the string value of a VehicleId.
pub fn get_vehicle_id_value(id: VehicleId) -> String {
  let VehicleId(value) = id
  value
}

// MARK: Plate Number

pub opaque type PlateNumber {
  PlateNumber(String)
}

// A PlateNumber is valid if its trimmed value is not empty.
pub fn new_plate_number(value: String) -> Result(PlateNumber, VehicleError) {
  let trimmed = string.trim(value)

  case trimmed {
    "" -> Error(EmptyPlateNumber)
    _ -> Ok(PlateNumber(trimmed))
  }
}

// Returns the string value of a PlateNumber.
pub fn get_plate_number_value(plate: PlateNumber) -> String {
  let PlateNumber(value) = plate
  value
}

// MARK: Vehicle Type

pub type VehicleType {
  Motorcycle
  Car
  Truck
}

// MARK: Vehicle

pub opaque type Vehicle {
  Vehicle(id: VehicleId, plate_number: PlateNumber, vehicle_type: VehicleType)
}

pub fn new_vehicle(
  id: VehicleId,
  plate_number: PlateNumber,
  vehicle_type: VehicleType,
) -> Vehicle {
  Vehicle(id: id, plate_number: plate_number, vehicle_type: vehicle_type)
}

pub fn get_vehicle_id(vehicle: Vehicle) -> VehicleId {
  let Vehicle(id: id, ..) = vehicle
  id
}

pub fn get_vehicle_plate_number(vehicle: Vehicle) -> PlateNumber {
  let Vehicle(plate_number: plate_number, ..) = vehicle
  plate_number
}

pub fn get_vehicle_type(vehicle: Vehicle) -> VehicleType {
  let Vehicle(vehicle_type: vehicle_type, ..) = vehicle
  vehicle_type
}
