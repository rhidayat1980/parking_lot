import application/exit_parking
import application/ports/exit_parking_transaction
import application/ports/repository_error

// MARK: Errors
pub type ExitParkingServiceError {
  TransactionFailed(repository_error.RepositoryError)
  ExitFailed(exit_parking.ExitParkingError)
  TransactionRollbackFailed(
    operation_error: exit_parking_transaction.ExitParkingTransactionError,
    rollback_error: repository_error.RepositoryError,
  )
}

pub fn error_message(error: ExitParkingServiceError) -> String {
  case error {
    TransactionFailed(repository_error.StorageError(message)) ->
      "Failed to complete parking exit: " <> message

    ExitFailed(exit_error) -> exit_parking.error_message(exit_error)

    TransactionRollbackFailed(operation_error, rollback_error) ->
      "Parking exit failed and rollback also failed. "
      <> "Operation error: "
      <> transaction_error_message(operation_error)
      <> ". Rollback error: "
      <> repository_error_message(rollback_error)
  }
}

fn transaction_error_message(
  error: exit_parking_transaction.ExitParkingTransactionError,
) -> String {
  case error {
    exit_parking_transaction.RepositoryFailed(repository_error) ->
      repository_error_message(repository_error)

    exit_parking_transaction.ExitFailed(exit_error) ->
      exit_parking.error_message(exit_error)

    exit_parking_transaction.RollbackFailed(operation_error, rollback_error) ->
      "Operation error: "
      <> transaction_error_message(operation_error)
      <> ". Rollback error: "
      <> repository_error_message(rollback_error)
  }
}

fn repository_error_message(error: repository_error.RepositoryError) -> String {
  case error {
    repository_error.StorageError(message) -> message
  }
}

// MARK: Service Dependencies
pub type ExitParkingService {
  ExitParkingService(
    transaction: exit_parking_transaction.ExitParkingTransaction,
  )
}

pub fn new(
  transaction: exit_parking_transaction.ExitParkingTransaction,
) -> ExitParkingService {
  ExitParkingService(transaction: transaction)
}

// MARK: Exit Parking
pub fn exit(
  service: ExitParkingService,
  request: exit_parking.ExitParkingRequest,
) -> Result(exit_parking.ExitParkingResult, ExitParkingServiceError) {
  let ExitParkingService(transaction: transaction) = service

  let exit_parking_transaction.ExitParkingTransaction(exit: exit) = transaction

  case exit(request) {
    Ok(exit_result) -> Ok(exit_result)

    Error(exit_parking_transaction.RepositoryFailed(error)) ->
      Error(TransactionFailed(error))

    Error(exit_parking_transaction.ExitFailed(error)) ->
      Error(ExitFailed(error))

    Error(exit_parking_transaction.RollbackFailed(
      operation_error,
      rollback_error,
    )) -> Error(TransactionRollbackFailed(operation_error, rollback_error))
  }
}
