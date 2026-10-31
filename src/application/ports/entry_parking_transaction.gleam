// import application/ports/repository_error
// import domain/parking_session
// import domain/parking_ticket

// // MARK: Entry Parking Transaction

// pub type EntryParkingTransaction {
//   EntryParkingTransaction(
//     save_entry: fn(parking_session.ParkingSession, parking_ticket.ParkingTicket) ->
//       Result(Nil, repository_error.RepositoryError),
//   )
// }

import application/entry_parking
import application/ports/repository_error

// MARK: Entry Parking Transaction

pub type EntryParkingTransaction {
  EntryParkingTransaction(
    enter: fn(entry_parking.EntryParkingRequest) ->
      Result(entry_parking.EntryParkingResult, EntryParkingTransactionError),
  )
}

// MARK: Errors

pub type EntryParkingTransactionError {
  RepositoryFailed(repository_error.RepositoryError)
  EntryFailed(entry_parking.EntryParkingError)
}
