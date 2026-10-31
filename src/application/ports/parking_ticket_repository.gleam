import application/ports/repository_error
import domain/parking_ticket
import gleam/option.{type Option}

// MARK: Parking Ticket Repository

pub type ParkingTicketRepository {
  ParkingTicketRepository(
    get_ticket: fn(parking_ticket.ParkingTicketId) ->
      Result(
        Option(parking_ticket.ParkingTicket),
        repository_error.RepositoryError,
      ),
  )
}
