import application/exit_parking
import application/ports/repository_error

// MARK: Exit Parking Transaction

pub type ExitParkingTransaction {
  ExitParkingTransaction(
    exit: fn(exit_parking.ExitParkingRequest) ->
      Result(exit_parking.ExitParkingResult, ExitParkingTransactionError),
  )
}

// MARK: Errors

pub type ExitParkingTransactionError {
  RepositoryFailed(repository_error.RepositoryError)
  ExitFailed(exit_parking.ExitParkingError)
  RollbackFailed(
    operation_error: ExitParkingTransactionError,
    rollback_error: repository_error.RepositoryError,
  )
}
