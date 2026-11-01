import application/entry_parking
import application/ports/entry_parking_transaction
import application/ports/repository_error

// MARK: Errors

pub type EntryParkingServiceError {
  TransactionFailed(repository_error.RepositoryError)
  EntryFailed(entry_parking.EntryParkingError)
  TransactionRollbackFailed(
    operation_error: entry_parking_transaction.EntryParkingTransactionError,
    rollback_error: repository_error.RepositoryError,
  )
}

pub fn error_message(error: EntryParkingServiceError) -> String {
  case error {
    TransactionFailed(repository_error) ->
      "Failed to complete parking entry: "
      <> repository_error.error_message(repository_error)

    EntryFailed(entry_error) -> entry_parking.error_message(entry_error)

    TransactionRollbackFailed(operation_error, rollback_error) ->
      "Parking entry failed and rollback also failed. "
      <> "Operation error: "
      <> transaction_error_message(operation_error)
      <> ". Rollback error: "
      <> repository_error_message(rollback_error)
  }
}

fn transaction_error_message(
  error: entry_parking_transaction.EntryParkingTransactionError,
) -> String {
  case error {
    entry_parking_transaction.RepositoryFailed(repository_error) ->
      repository_error_message(repository_error)

    entry_parking_transaction.EntryFailed(entry_error) ->
      entry_parking.error_message(entry_error)

    entry_parking_transaction.RollbackFailed(
      operation_error: operation_error,
      rollback_error: rollback_error,
    ) ->
      "Operation error: "
      <> transaction_error_message(operation_error)
      <> ". Rollback error: "
      <> repository_error_message(rollback_error)
  }
}

fn repository_error_message(error: repository_error.RepositoryError) -> String {
  repository_error.error_message(error)
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

    Error(entry_parking_transaction.RollbackFailed(
      operation_error: operation_error,
      rollback_error: rollback_error,
    )) ->
      Error(TransactionRollbackFailed(
        operation_error: operation_error,
        rollback_error: rollback_error,
      ))
  }
}
