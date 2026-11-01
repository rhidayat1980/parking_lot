import application/ports/repository_error
import sqlight

/// Membuka koneksi ke database utama.
pub fn connect() -> Result(sqlight.Connection, repository_error.RepositoryError) {
  connect_to("priv/repo/parking_lot.db")
}

/// Membuka koneksi ke database berdasarkan path.
///
/// Foreign key diaktifkan untuk setiap koneksi.
pub fn connect_to(
  path: String,
) -> Result(sqlight.Connection, repository_error.RepositoryError) {
  case sqlight.open(path) {
    Ok(connection) -> {
      case sqlight.exec("PRAGMA foreign_keys = ON;", on: connection) {
        Ok(Nil) -> Ok(connection)

        Error(error) -> {
          let repository_error = to_repository_error(error)

          case sqlight.close(connection) {
            Ok(Nil) -> Error(repository_error)
            Error(_) -> Error(repository_error)
          }
        }
      }
    }

    Error(error) -> Error(to_repository_error(error))
  }
}

/// Mengubah error SQLight menjadi RepositoryError.
fn to_repository_error(
  error: sqlight.Error,
) -> repository_error.RepositoryError {
  case error {
    sqlight.SqlightError(_, message, _) -> repository_error.ReadFailed(message)
  }
}
