import domain/vehicle
import gleam/string
import interface/cli/display
import interface/cli/terminal_input
import youid/uuid

/// Errors produced while parsing a vehicle type selection.
pub type VehicleTypeInputError {
  EmptyInput
  UnknownOption
}

/// Converts a numbered selection into a vehicle type.
pub fn parse_vehicle_type(
  raw_input: String,
) -> Result(vehicle.VehicleType, VehicleTypeInputError) {
  case string.trim(raw_input) {
    "" -> Error(EmptyInput)
    "1" -> Ok(vehicle.Motorcycle)
    "2" -> Ok(vehicle.Car)
    "3" -> Ok(vehicle.Truck)
    _ -> Error(UnknownOption)
  }
}

/// Collects vehicle information from the terminal.
pub fn read_vehicle() -> Result(vehicle.Vehicle, Nil) {
  display.heading("Vehicle Entry")

  case read_plate_number() {
    Ok(plate_number) ->
      case read_vehicle_type() {
        Ok(vehicle_type) -> create_vehicle(plate_number, vehicle_type)
        Error(Nil) -> Error(Nil)
      }

    Error(Nil) -> Error(Nil)
  }
}

fn read_plate_number() -> Result(vehicle.PlateNumber, Nil) {
  display.prompt("Enter vehicle plate number: ")

  case terminal_input.read_line() {
    Ok(raw_input) ->
      case vehicle.new_plate_number(raw_input) {
        Ok(plate_number) -> Ok(plate_number)
        Error(vehicle.EmptyPlateNumber) -> {
          display.warning("Plate number cannot be empty.")
          read_plate_number()
        }
        Error(vehicle.EmptyVehicleId) -> {
          display.error("Unexpected vehicle ID validation error.")
          Error(Nil)
        }
      }

    Error(Nil) -> Error(Nil)
  }
}

fn read_vehicle_type() -> Result(vehicle.VehicleType, Nil) {
  display.separator()
  display.info("Select vehicle type:")
  display.info("1. Motorcycle")
  display.info("2. Car")
  display.info("3. Truck")
  display.prompt("Select vehicle type: ")

  case terminal_input.read_line() {
    Ok(raw_input) ->
      case parse_vehicle_type(raw_input) {
        Ok(vehicle_type) -> Ok(vehicle_type)

        Error(EmptyInput) -> {
          display.warning("Vehicle type cannot be empty.")
          read_vehicle_type()
        }

        Error(UnknownOption) -> {
          display.warning("Unknown vehicle type. Please select 1, 2, or 3.")
          read_vehicle_type()
        }
      }

    Error(Nil) -> Error(Nil)
  }
}

fn create_vehicle(
  plate_number: vehicle.PlateNumber,
  vehicle_type: vehicle.VehicleType,
) -> Result(vehicle.Vehicle, Nil) {
  let generated_id = uuid.v7_string()

  case vehicle.new_vehicle_id(generated_id) {
    Ok(vehicle_id) -> {
      let new_vehicle =
        vehicle.new_vehicle(vehicle_id, plate_number, vehicle_type)

      display.success("Vehicle information accepted.")
      Ok(new_vehicle)
    }

    Error(_) -> {
      display.error("Failed to generate vehicle ID.")
      Error(Nil)
    }
  }
}
