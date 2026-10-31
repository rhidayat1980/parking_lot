import domain/parking_slot
import domain/vehicle
import gleam/option
import gleam/result
import gleam/string

// MARK: Errors

pub type ParkingSessionError {
  EmptyParkingSessionId
  InvalidEntryTime
  InvalidExitTime
  ParkingSessionAlreadyClosed
}

pub fn error_message(error: ParkingSessionError) -> String {
  case error {
    EmptyParkingSessionId -> "Parking session ID cannot be empty"
    InvalidEntryTime -> "Entry time cannot be negative"
    InvalidExitTime -> "Exit time cannot be earlier than entry time"
    ParkingSessionAlreadyClosed -> "Parking session is already closed"
  }
}

// MARK: Session State

pub type SessionState {
  Active
  Closed(exit_time: Int)
}

// MARK: Parking Session ID

pub opaque type ParkingSessionId {
  ParkingSessionId(String)
}

// MARK: Parking Session

pub opaque type ParkingSession {
  ParkingSession(
    id: ParkingSessionId,
    vehicle_id: vehicle.VehicleId,
    slot_id: parking_slot.ParkingSlotId,
    entry_time: Int,
    state: SessionState,
  )
}

// MARK: Constructor

fn validate_parking_session_id(
  value: String,
) -> Result(Nil, ParkingSessionError) {
  case value == "" {
    True -> Error(EmptyParkingSessionId)
    False -> Ok(Nil)
  }
}

fn validate_entry_time(entry_time: Int) -> Result(Nil, ParkingSessionError) {
  case entry_time >= 0 {
    True -> Ok(Nil)
    False -> Error(InvalidEntryTime)
  }
}

pub fn new_parking_session_id(
  value: String,
) -> Result(ParkingSessionId, ParkingSessionError) {
  let trimmed = string.trim(value)

  use _ <- result.try(validate_parking_session_id(trimmed))

  Ok(ParkingSessionId(trimmed))
}

pub fn get_parking_session_id_value(id: ParkingSessionId) -> String {
  let ParkingSessionId(value) = id
  value
}

pub fn new_parking_session(
  id: ParkingSessionId,
  vehicle_id: vehicle.VehicleId,
  slot_id: parking_slot.ParkingSlotId,
  entry_time: Int,
) -> Result(ParkingSession, ParkingSessionError) {
  use _ <- result.try(validate_entry_time(entry_time))

  Ok(ParkingSession(
    id: id,
    vehicle_id: vehicle_id,
    slot_id: slot_id,
    entry_time: entry_time,
    state: Active,
  ))
}

// MARK: Accessors

pub fn get_parking_session_id(session: ParkingSession) -> ParkingSessionId {
  session.id
}

pub fn get_parking_session_vehicle_id(
  session: ParkingSession,
) -> vehicle.VehicleId {
  session.vehicle_id
}

pub fn get_parking_session_slot_id(
  session: ParkingSession,
) -> parking_slot.ParkingSlotId {
  session.slot_id
}

pub fn get_parking_session_entry_time(session: ParkingSession) -> Int {
  session.entry_time
}

pub fn get_parking_session_state(session: ParkingSession) -> SessionState {
  session.state
}

pub fn get_parking_session_exit_time(
  session: ParkingSession,
) -> option.Option(Int) {
  case session.state {
    Active -> option.None
    Closed(exit_time) -> option.Some(exit_time)
  }
}

// MARK: Close Parking Session

fn validate_session_is_active(
  state: SessionState,
) -> Result(Nil, ParkingSessionError) {
  case state {
    Active -> Ok(Nil)
    Closed(_) -> Error(ParkingSessionAlreadyClosed)
  }
}

fn validate_exit_time(
  entry_time: Int,
  exit_time: Int,
) -> Result(Nil, ParkingSessionError) {
  case exit_time >= entry_time {
    True -> Ok(Nil)
    False -> Error(InvalidExitTime)
  }
}

pub fn close_parking_session(
  session: ParkingSession,
  exit_time: Int,
) -> Result(ParkingSession, ParkingSessionError) {
  use _ <- result.try(validate_session_is_active(session.state))
  use _ <- result.try(validate_exit_time(session.entry_time, exit_time))

  Ok(ParkingSession(
    id: session.id,
    vehicle_id: session.vehicle_id,
    slot_id: session.slot_id,
    entry_time: session.entry_time,
    state: Closed(exit_time),
  ))
}
