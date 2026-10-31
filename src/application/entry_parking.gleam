import domain/floor
import domain/parking_allocation
import domain/parking_session
import domain/parking_slot
import domain/parking_ticket
import domain/vehicle
import gleam/result

// MARK: Errors

pub type EntryParkingError {
  NoAvailableParkingSlot
  AllocationFailed(parking_allocation.ParkingAllocationError)
}

pub fn error_message(error: EntryParkingError) -> String {
  case error {
    NoAvailableParkingSlot -> "No available parking slot for this vehicle"

    AllocationFailed(allocation_error) ->
      parking_allocation.error_message(allocation_error)
  }
}

// MARK: Entry Parking Request

pub type EntryParkingRequest {
  EntryParkingRequest(
    session_id: parking_session.ParkingSessionId,
    ticket_id: parking_ticket.ParkingTicketId,
    vehicle: vehicle.Vehicle,
    entry_time: Int,
  )
}

// MARK: Entry Parking Result

pub type EntryParkingResult {
  EntryParkingResult(
    floor_id: floor.ParkingFloorId,
    slot: parking_slot.ParkingSlot,
    session: parking_session.ParkingSession,
    ticket: parking_ticket.ParkingTicket,
  )
}

// MARK: Entry Parking

pub fn enter_parking(
  floors: List(floor.ParkingFloor),
  existing_sessions: List(parking_session.ParkingSession),
  request: EntryParkingRequest,
) -> Result(EntryParkingResult, EntryParkingError) {
  let EntryParkingRequest(
    session_id: session_id,
    ticket_id: ticket_id,
    vehicle: candidate_vehicle,
    entry_time: entry_time,
  ) = request

  use #(floor_id, slot, session) <- result.try(find_available_slot(
    floors,
    existing_sessions,
    session_id,
    candidate_vehicle,
    entry_time,
  ))

  let ticket =
    parking_ticket.new_parking_ticket(ticket_id, session_id, entry_time)

  Ok(EntryParkingResult(
    floor_id: floor_id,
    slot: slot,
    session: session,
    ticket: ticket,
  ))
}

// MARK: Slot Search

fn find_available_slot(
  floors: List(floor.ParkingFloor),
  existing_sessions: List(parking_session.ParkingSession),
  session_id: parking_session.ParkingSessionId,
  candidate_vehicle: vehicle.Vehicle,
  entry_time: Int,
) -> Result(
  #(
    floor.ParkingFloorId,
    parking_slot.ParkingSlot,
    parking_session.ParkingSession,
  ),
  EntryParkingError,
) {
  case floors {
    [] -> Error(NoAvailableParkingSlot)

    [current_floor, ..remaining_floors] -> {
      let floor_id = floor.get_parking_floor_id(current_floor)
      let slots = floor.get_parking_floor_slots(current_floor)

      case
        find_available_slot_in_floor(
          slots,
          floor_id,
          existing_sessions,
          session_id,
          candidate_vehicle,
          entry_time,
        )
      {
        Ok(allocation) -> Ok(allocation)

        Error(NoAvailableParkingSlot) ->
          find_available_slot(
            remaining_floors,
            existing_sessions,
            session_id,
            candidate_vehicle,
            entry_time,
          )

        Error(error) -> Error(error)
      }
    }
  }
}

// MARK: Floor Slot Search

fn find_available_slot_in_floor(
  slots: List(parking_slot.ParkingSlot),
  floor_id: floor.ParkingFloorId,
  existing_sessions: List(parking_session.ParkingSession),
  session_id: parking_session.ParkingSessionId,
  candidate_vehicle: vehicle.Vehicle,
  entry_time: Int,
) -> Result(
  #(
    floor.ParkingFloorId,
    parking_slot.ParkingSlot,
    parking_session.ParkingSession,
  ),
  EntryParkingError,
) {
  case slots {
    [] -> Error(NoAvailableParkingSlot)

    [current_slot, ..remaining_slots] ->
      try_allocate_slot(
        current_slot,
        remaining_slots,
        floor_id,
        existing_sessions,
        session_id,
        candidate_vehicle,
        entry_time,
      )
  }
}

// MARK: Slot Allocation Attempt

fn try_allocate_slot(
  slot: parking_slot.ParkingSlot,
  remaining_slots: List(parking_slot.ParkingSlot),
  floor_id: floor.ParkingFloorId,
  existing_sessions: List(parking_session.ParkingSession),
  session_id: parking_session.ParkingSessionId,
  candidate_vehicle: vehicle.Vehicle,
  entry_time: Int,
) -> Result(
  #(
    floor.ParkingFloorId,
    parking_slot.ParkingSlot,
    parking_session.ParkingSession,
  ),
  EntryParkingError,
) {
  let request =
    parking_allocation.ParkingAllocationRequest(
      session_id: session_id,
      vehicle: candidate_vehicle,
      slot: slot,
      entry_time: entry_time,
    )

  case parking_allocation.allocate_parking_session(existing_sessions, request) {
    Ok(session) -> Ok(#(floor_id, slot, session))

    Error(parking_allocation.VehicleTypeNotSupported) ->
      find_available_slot_in_floor(
        remaining_slots,
        floor_id,
        existing_sessions,
        session_id,
        candidate_vehicle,
        entry_time,
      )

    Error(parking_allocation.ParkingSlotOccupied) ->
      find_available_slot_in_floor(
        remaining_slots,
        floor_id,
        existing_sessions,
        session_id,
        candidate_vehicle,
        entry_time,
      )

    Error(error) -> Error(AllocationFailed(error))
  }
}
