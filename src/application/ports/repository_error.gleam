pub type RepositoryError {
  ReadFailed(String)
  WriteFailed(String)
  InvalidPersistedData(String)
}

pub fn error_message(error: RepositoryError) -> String {
  case error {
    ReadFailed(message) -> "Failed to read from repository: " <> message
    WriteFailed(message) -> "Failed to write to repository: " <> message
    InvalidPersistedData(message) -> "Invalid persisted data: " <> message
  }
}
