import domain/parking_session
import domain/parking_slot
import domain/vehicle
import gleam/list
import gleam/result

// MARK: Errors

pub type ParkingAllocationError {
  VehicleAlreadyParked
  ParkingSlotOccupied
  VehicleTypeNotSupported
  InvalidEntryTime
  InvalidParkingSession
}

pub type ParkingAllocationResult(a) =
  Result(a, ParkingAllocationError)

pub fn error_message(error: ParkingAllocationError) -> String {
  case error {
    VehicleAlreadyParked -> "Vehicle already has an active parking session"

    ParkingSlotOccupied -> "Parking slot is already occupied"

    VehicleTypeNotSupported ->
      "Vehicle type is not supported by this parking slot"

    InvalidEntryTime -> "Entry time cannot be negative"

    InvalidParkingSession -> "Could not create a valid parking session"
  }
}

// MARK: Allocation Request

pub type ParkingAllocationRequest {
  ParkingAllocationRequest(
    session_id: parking_session.ParkingSessionId,
    vehicle: vehicle.Vehicle,
    slot: parking_slot.ParkingSlot,
    entry_time: Int,
  )
}

// MARK: Allocation

pub fn allocate_parking_session(
  existing_sessions: List(parking_session.ParkingSession),
  request: ParkingAllocationRequest,
) -> ParkingAllocationResult(parking_session.ParkingSession) {
  let ParkingAllocationRequest(
    session_id: session_id,
    vehicle: candidate_vehicle,
    slot: slot,
    entry_time: entry_time,
  ) = request

  let vehicle_id = vehicle.get_vehicle_id(candidate_vehicle)
  let slot_id = parking_slot.get_parking_slot_id(slot)

  use _ <- result.try(validate_vehicle_type(candidate_vehicle, slot))

  use _ <- result.try(validate_vehicle_availability(
    existing_sessions,
    vehicle_id,
  ))

  use _ <- result.try(validate_slot_availability(existing_sessions, slot_id))

  construct_parking_session(session_id, vehicle_id, slot_id, entry_time)
}

// MARK: Validation

fn validate_vehicle_type(
  candidate_vehicle: vehicle.Vehicle,
  slot: parking_slot.ParkingSlot,
) -> ParkingAllocationResult(Nil) {
  case parking_slot.supports_vehicle(slot, candidate_vehicle) {
    True -> Ok(Nil)
    False -> Error(VehicleTypeNotSupported)
  }
}

fn validate_vehicle_availability(
  sessions: List(parking_session.ParkingSession),
  vehicle_id: vehicle.VehicleId,
) -> ParkingAllocationResult(Nil) {
  case vehicle_has_active_session(sessions, vehicle_id) {
    True -> Error(VehicleAlreadyParked)
    False -> Ok(Nil)
  }
}

fn validate_slot_availability(
  sessions: List(parking_session.ParkingSession),
  slot_id: parking_slot.ParkingSlotId,
) -> ParkingAllocationResult(Nil) {
  case slot_has_active_session(sessions, slot_id) {
    True -> Error(ParkingSlotOccupied)
    False -> Ok(Nil)
  }
}

// MARK: Active Session Queries

fn vehicle_has_active_session(
  sessions: List(parking_session.ParkingSession),
  vehicle_id: vehicle.VehicleId,
) -> Bool {
  list.any(sessions, fn(session) {
    case parking_session.get_parking_session_state(session) {
      parking_session.Active ->
        parking_session.get_parking_session_vehicle_id(session) == vehicle_id

      parking_session.Closed(_) -> False
    }
  })
}

fn slot_has_active_session(
  sessions: List(parking_session.ParkingSession),
  slot_id: parking_slot.ParkingSlotId,
) -> Bool {
  list.any(sessions, fn(session) {
    case parking_session.get_parking_session_state(session) {
      parking_session.Active ->
        parking_session.get_parking_session_slot_id(session) == slot_id

      parking_session.Closed(_) -> False
    }
  })
}

// MARK: Session Construction

fn construct_parking_session(
  session_id: parking_session.ParkingSessionId,
  vehicle_id: vehicle.VehicleId,
  slot_id: parking_slot.ParkingSlotId,
  entry_time: Int,
) -> ParkingAllocationResult(parking_session.ParkingSession) {
  case
    parking_session.new_parking_session(
      session_id,
      vehicle_id,
      slot_id,
      entry_time,
    )
  {
    Ok(session) -> Ok(session)

    Error(parking_session.InvalidEntryTime) -> Error(InvalidEntryTime)

    Error(_) -> Error(InvalidParkingSession)
  }
}
