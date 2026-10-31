import domain/vehicle
import gleam/string

// MARK: Errors

pub type ParkingSlotError {
  EmptyParkingSlotId
}

pub fn error_message(error: ParkingSlotError) -> String {
  case error {
    EmptyParkingSlotId -> "Parking slot ID cannot be empty"
  }
}

// MARK: Parking Slot ID

pub opaque type ParkingSlotId {
  ParkingSlotId(String)
}

pub fn new_parking_slot_id(
  value: String,
) -> Result(ParkingSlotId, ParkingSlotError) {
  let trimmed = string.trim(value)

  case trimmed {
    "" -> Error(EmptyParkingSlotId)
    _ -> Ok(ParkingSlotId(trimmed))
  }
}

pub fn get_parking_slot_id_value(id: ParkingSlotId) -> String {
  let ParkingSlotId(value) = id
  value
}

// MARK: Parking Slot

pub opaque type ParkingSlot {
  ParkingSlot(id: ParkingSlotId, supported_vehicle_type: vehicle.VehicleType)
}

pub fn new_parking_slot(
  id: ParkingSlotId,
  supported_vehicle_type: vehicle.VehicleType,
) -> ParkingSlot {
  ParkingSlot(id: id, supported_vehicle_type: supported_vehicle_type)
}

pub fn get_parking_slot_id(slot: ParkingSlot) -> ParkingSlotId {
  let ParkingSlot(id: id, ..) = slot
  id
}

pub fn get_supported_vehicle_type(slot: ParkingSlot) -> vehicle.VehicleType {
  let ParkingSlot(supported_vehicle_type: vehicle_type, ..) = slot
  vehicle_type
}

// MARK: Vehicle Compatibility

pub fn supports_vehicle(slot: ParkingSlot, vehicle: vehicle.Vehicle) -> Bool {
  get_supported_vehicle_type(slot) == vehicle.get_vehicle_type(vehicle)
}
