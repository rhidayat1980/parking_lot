import application/entry_parking
import application/ports/entry_parking_transaction
import application/ports/repository_error

// MARK: Errors

pub type EntryParkingServiceError {
  TransactionFailed(repository_error.RepositoryError)
  EntryFailed(entry_parking.EntryParkingError)
}

pub fn error_message(error: EntryParkingServiceError) -> String {
  case error {
    TransactionFailed(repository_error.StorageError(message)) ->
      "Failed to complete parking entry: " <> message
    EntryFailed(entry_error) -> entry_parking.error_message(entry_error)
  }
}

// MARK: Service Dependencies

pub type EntryParkingService {
  EntryParkingService(
    transaction: entry_parking_transaction.EntryParkingTransaction,
  )
}

pub fn new(
  transaction: entry_parking_transaction.EntryParkingTransaction,
) -> EntryParkingService {
  EntryParkingService(transaction: transaction)
}

// MARK: Enter Parking

pub fn enter(
  service: EntryParkingService,
  request: entry_parking.EntryParkingRequest,
) -> Result(entry_parking.EntryParkingResult, EntryParkingServiceError) {
  let EntryParkingService(transaction: transaction) = service

  let entry_parking_transaction.EntryParkingTransaction(enter: enter) =
    transaction

  case enter(request) {
    Ok(entry_result) -> Ok(entry_result)
    Error(entry_parking_transaction.RepositoryFailed(error)) ->
      Error(TransactionFailed(error))
    Error(entry_parking_transaction.EntryFailed(error)) ->
      Error(EntryFailed(error))
  }
}
