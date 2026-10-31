import domain/parking_session
import gleam/string

// MARK: Errors

pub type ParkingTicketError {
  EmptyParkingTicketId
}

pub fn error_message(error: ParkingTicketError) -> String {
  case error {
    EmptyParkingTicketId -> "Parking ticket ID cannot be empty"
  }
}

// MARK: Parking Ticket ID

pub opaque type ParkingTicketId {
  ParkingTicketId(String)
}

pub fn new_parking_ticket_id(
  value: String,
) -> Result(ParkingTicketId, ParkingTicketError) {
  let trimmed = string.trim(value)

  case trimmed {
    "" -> Error(EmptyParkingTicketId)
    _ -> Ok(ParkingTicketId(trimmed))
  }
}

pub fn get_parking_ticket_id_value(id: ParkingTicketId) -> String {
  let ParkingTicketId(value) = id
  value
}

// MARK: Parking Ticket

pub opaque type ParkingTicket {
  ParkingTicket(
    id: ParkingTicketId,
    session_id: parking_session.ParkingSessionId,
    issued_at: Int,
  )
}

// MARK: Constructor

pub fn new_parking_ticket(
  id: ParkingTicketId,
  session_id: parking_session.ParkingSessionId,
  issued_at: Int,
) -> ParkingTicket {
  ParkingTicket(id: id, session_id: session_id, issued_at: issued_at)
}

// MARK: Accessors

pub fn get_parking_ticket_id(ticket: ParkingTicket) -> ParkingTicketId {
  let ParkingTicket(id: id, ..) = ticket
  id
}

pub fn get_parking_ticket_session_id(
  ticket: ParkingTicket,
) -> parking_session.ParkingSessionId {
  let ParkingTicket(session_id: session_id, ..) = ticket
  session_id
}

pub fn get_parking_ticket_issued_at(ticket: ParkingTicket) -> Int {
  let ParkingTicket(issued_at: issued_at, ..) = ticket
  issued_at
}
