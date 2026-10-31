import domain/vehicle
import gleam/io

pub fn main() -> Nil {
  case register_example_vehicle() {
    Ok(_) -> io.println("Vehicle created successfully")
    Error(error) -> io.println(vehicle.error_message(error))
  }
}

pub fn register_example_vehicle() -> Result(
  vehicle.Vehicle,
  vehicle.VehicleError,
) {
  case vehicle.new_vehicle_id("V001") {
    Error(error) -> Error(error)
    Ok(id) -> {
      case vehicle.new_plate_number("B 1234 ABC") {
        Error(error) -> Error(error)
        Ok(plate) -> {
          Ok(vehicle.new_vehicle(id, plate, vehicle.Car))
        }
      }
    }
  }
}
