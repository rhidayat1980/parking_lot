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
  RollbackFailed(
    operation_error: EntryParkingTransactionError,
    rollback_error: repository_error.RepositoryError,
  )
}
