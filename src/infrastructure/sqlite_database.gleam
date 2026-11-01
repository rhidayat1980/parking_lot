import application/ports/repository_error
import gleam/result
import infrastructure/sqlite_connection
import infrastructure/sqlite_migration
import sqlight

const migrations_dir = "priv/repo/migrations"

/// Open main database and make sure migrations done already
/// use the same connection for migration and repository
pub fn connect() -> Result(sqlight.Connection, repository_error.RepositoryError) {
  use db <- result.try(sqlite_connection.connect())

  case sqlite_migration.migrate(db, migrations_dir) {
    Ok(Nil) -> Ok(db)

    Error(message) -> {
      let _ = sqlight.close(db)

      Error(repository_error.StorageError(
        "Database migration failed: " <> message,
      ))
    }
  }
}
