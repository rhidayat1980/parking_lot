import gleam/dynamic/decode
import gleam/list
import gleam/result

import infrastructure/sqlite_connection as connection
import sqlight

// const initial_migration_version = 1

// const initial_migration_name = "001_create_parking_schema.sql"

const required_tables = [
  "parking_floors",
  "parking_slots",
  "vehicles",
  "parking_sessions",
  "parking_tickets",
]

/// Mencatat migrasi awal untuk database yang schema-nya sudah ada.
///
/// Fungsi ini tidak menjalankan ulang SQL migrasi awal.
/// Database harus sudah memiliki seluruh tabel yang dibutuhkan.
pub fn adopt_existing_schema() -> Result(Nil, String) {
  use db <- result.try(
    connection.connect()
    |> result.map_error(fn(error) {
      case error {
        _ -> "Gagal membuka koneksi database."
      }
    }),
  )

  let outcome = adopt_on_connection(db)

  let close_result = sqlight.close(db)

  case outcome {
    Error(message) -> Error(message)
    Ok(Nil) ->
      case close_result {
        Ok(Nil) -> Ok(Nil)
        Error(_) -> Error("Gagal menutup koneksi database.")
      }
  }
}

fn adopt_on_connection(db: sqlight.Connection) -> Result(Nil, String) {
  use _ <- result.try(
    sqlight.exec(
      "
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      ",
      on: db,
    )
    |> result.map_error(fn(_) { "Gagal membuat tabel schema_migrations." }),
  )

  use tables <- result.try(
    sqlight.query(
      "
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN (
          'parking_floors',
          'parking_slots',
          'vehicles',
          'parking_sessions',
          'parking_tickets'
        );
      ",
      on: db,
      with: [],
      expecting: decode.field(0, decode.string, fn(name) {
        decode.success(name)
      }),
    )
    |> result.map_error(fn(_) { "Gagal memeriksa tabel database." }),
  )

  case list.all(required_tables, fn(table) { list.contains(tables, table) }) {
    False -> Error("Schema database belum lengkap. Migrasi awal tidak dicatat.")

    True -> record_initial_migration(db)
  }
}

fn record_initial_migration(db: sqlight.Connection) -> Result(Nil, String) {
  use _ <- result.try(
    sqlight.exec(
      "
      INSERT INTO schema_migrations (version, name)
      VALUES (1, '001_create_parking_schema.sql')
      ON CONFLICT(version) DO NOTHING;
      ",
      on: db,
    )
    |> result.map_error(fn(_) { "Gagal mencatat migrasi awal." }),
  )

  Ok(Nil)
}
