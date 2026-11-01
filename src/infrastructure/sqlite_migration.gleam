import gleam/dynamic/decode
import gleam/list
import gleam/result

import migrant
import sqlight

const required_tables = [
  "parking_floors",
  "parking_slots",
  "vehicles",
  "parking_sessions",
  "parking_tickets",
]

const initial_migration_name = "001_create_parking_schema"

/// Menjalankan migrasi database.
///
/// Database baru akan dimigrasikan menggunakan Migrant.
/// Database lama yang sudah memiliki schema lengkap dan
/// legacy migration history akan diadopsi ke Migrant.
pub fn migrate(
  db: sqlight.Connection,
  migrations_dir: String,
) -> Result(Nil, String) {
  use tables <- result.try(load_table_names(db))

  let existing_domain_tables =
    list.filter(tables, fn(table) { list.contains(required_tables, table) })

  case list.length(existing_domain_tables) {
    0 -> migrate_new_database(db, tables, migrations_dir)

    5 -> migrate_existing_database(db, tables)

    _ ->
      Error(
        "Schema database tidak lengkap. Migrasi dihentikan untuk mencegah perubahan schema yang tidak aman.",
      )
  }
}

fn migrate_new_database(
  db: sqlight.Connection,
  tables: List(String),
  migrations_dir: String,
) -> Result(Nil, String) {
  case list.contains(tables, "schema_migrations") {
    True ->
      Error(
        "Database memiliki schema_migrations tetapi tidak memiliki schema domain. Pemeriksaan manual diperlukan.",
      )

    False ->
      case list.contains(tables, "__migrations") {
        True ->
          Error(
            "Database memiliki __migrations tetapi tidak memiliki schema domain. Pemeriksaan manual diperlukan.",
          )

        False ->
          migrant.migrate(db, migrations_dir)
          |> result.map_error(fn(_) {
            "Gagal menjalankan migrasi database menggunakan Migrant."
          })
      }
  }
}

fn migrate_existing_database(
  db: sqlight.Connection,
  tables: List(String),
) -> Result(Nil, String) {
  case list.contains(tables, "__migrations") {
    True -> {
      use applied <- result.try(
        migrant_migration_is_applied(db)
        |> result.map_error(fn(_) {
          "Gagal memeriksa migration history Migrant."
        }),
      )

      case applied {
        True -> Ok(Nil)

        False ->
          Error(
            "Schema domain sudah ada tetapi migration history Migrant tidak mencatat migrasi awal.",
          )
      }
    }

    False -> adopt_legacy_database(db, tables)
  }
}

fn adopt_legacy_database(
  db: sqlight.Connection,
  tables: List(String),
) -> Result(Nil, String) {
  case list.contains(tables, "schema_migrations") {
    False ->
      Error(
        "Schema domain sudah ada tetapi legacy migration history tidak ditemukan.",
      )

    True -> {
      use legacy_applied <- result.try(
        legacy_migration_is_applied(db)
        |> result.map_error(fn(_) {
          "Gagal memeriksa legacy migration history."
        }),
      )

      case legacy_applied {
        False ->
          Error(
            "Schema domain sudah ada tetapi migrasi awal tidak tercatat pada legacy migration history.",
          )

        True -> record_migrant_migration(db)
      }
    }
  }
}

fn load_table_names(db: sqlight.Connection) -> Result(List(String), String) {
  sqlight.query(
    "
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name NOT LIKE 'sqlite_%';
    ",
    on: db,
    with: [],
    expecting: decode.field(0, decode.string, fn(name) { decode.success(name) }),
  )
  |> result.map_error(fn(_) { "Gagal membaca daftar tabel database." })
}

fn legacy_migration_is_applied(
  db: sqlight.Connection,
) -> Result(Bool, sqlight.Error) {
  use versions <- result.try(sqlight.query(
    "
      SELECT name
      FROM schema_migrations
      WHERE version = 1;
      ",
    on: db,
    with: [],
    expecting: decode.field(0, decode.string, fn(name) { decode.success(name) }),
  ))

  Ok(list.contains(versions, "001_create_parking_schema.sql"))
}

fn migrant_migration_is_applied(
  db: sqlight.Connection,
) -> Result(Bool, sqlight.Error) {
  use names <- result.try(sqlight.query(
    "
      SELECT name
      FROM __migrations
      WHERE name = ?;
      ",
    on: db,
    with: [sqlight.text(initial_migration_name)],
    expecting: decode.field(0, decode.string, fn(name) { decode.success(name) }),
  ))

  Ok(list.contains(names, initial_migration_name))
}

fn record_migrant_migration(db: sqlight.Connection) -> Result(Nil, String) {
  case sqlight.exec("BEGIN IMMEDIATE;", on: db) {
    Error(_) -> Error("Gagal memulai transaksi adopsi migration.")

    Ok(Nil) -> {
      let outcome = record_migrant_migration_in_transaction(db)

      case outcome {
        Ok(Nil) ->
          case sqlight.exec("COMMIT;", on: db) {
            Ok(Nil) -> Ok(Nil)
            Error(_) -> {
              rollback_migration_adoption(db)
              Error("Gagal melakukan commit adopsi migration.")
            }
          }

        Error(message) -> {
          rollback_migration_adoption(db)
          Error(message)
        }
      }
    }
  }
}

fn record_migrant_migration_in_transaction(
  db: sqlight.Connection,
) -> Result(Nil, String) {
  use _ <- result.try(
    sqlight.exec(
      "
      CREATE TABLE IF NOT EXISTS __migrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      ",
      on: db,
    )
    |> result.map_error(fn(_) {
      "Gagal membuat tabel migration history Migrant."
    }),
  )

  use _ <- result.try(
    sqlight.exec(
      "
      INSERT INTO __migrations (name)
      SELECT '001_create_parking_schema'
      WHERE NOT EXISTS (
        SELECT 1
        FROM __migrations
        WHERE name = '001_create_parking_schema'
      );
      ",
      on: db,
    )
    |> result.map_error(fn(_) {
      "Gagal mengadopsi legacy migration ke Migrant."
    }),
  )

  Ok(Nil)
}

fn rollback_migration_adoption(db: sqlight.Connection) {
  let _ = sqlight.exec("ROLLBACK;", on: db)

  Nil
}
