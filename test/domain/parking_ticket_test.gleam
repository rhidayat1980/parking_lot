import domain/parking_session
import domain/parking_ticket
import gleeunit/should

pub fn parking_ticket_id_rejects_empty_string_test() {
  parking_ticket.new_parking_ticket_id("")
  |> should.equal(Error(parking_ticket.EmptyParkingTicketId))
}

pub fn parking_ticket_id_rejects_whitespace_test() {
  parking_ticket.new_parking_ticket_id("   ")
  |> should.equal(Error(parking_ticket.EmptyParkingTicketId))
}

pub fn parking_ticket_id_trims_whitespace_test() {
  let result = parking_ticket.new_parking_ticket_id(" PT001 ")

  case result {
    Ok(id) ->
      parking_ticket.get_parking_ticket_id_value(id)
      |> should.equal("PT001")

    Error(_) -> should.fail()
  }
}

pub fn new_parking_ticket_stores_ticket_id_test() {
  let assert Ok(ticket_id) = parking_ticket.new_parking_ticket_id("PT001")

  let assert Ok(session_id) = parking_session.new_parking_session_id("PS001")

  let ticket =
    parking_ticket.new_parking_ticket(ticket_id, session_id, 1_798_000_000)

  parking_ticket.get_parking_ticket_id(ticket)
  |> parking_ticket.get_parking_ticket_id_value
  |> should.equal("PT001")
}

pub fn new_parking_ticket_stores_session_id_test() {
  let assert Ok(ticket_id) = parking_ticket.new_parking_ticket_id("PT001")

  let assert Ok(session_id) = parking_session.new_parking_session_id("PS001")

  let ticket =
    parking_ticket.new_parking_ticket(ticket_id, session_id, 1_798_000_000)

  parking_ticket.get_parking_ticket_session_id(ticket)
  |> parking_session.get_parking_session_id_value
  |> should.equal("PS001")
}

pub fn new_parking_ticket_stores_issued_at_test() {
  let assert Ok(ticket_id) = parking_ticket.new_parking_ticket_id("PT001")

  let assert Ok(session_id) = parking_session.new_parking_session_id("PS001")

  let ticket =
    parking_ticket.new_parking_ticket(ticket_id, session_id, 1_798_000_000)

  parking_ticket.get_parking_ticket_issued_at(ticket)
  |> should.equal(1_798_000_000)
}
