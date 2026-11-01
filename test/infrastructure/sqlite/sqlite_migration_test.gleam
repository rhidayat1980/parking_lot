import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import infrastructure/sqlite_connection as connection
import infrastructure/sqlite_migration as migration
import simplifile
import sqlight

const migrations_dir = "priv/repo/migrations"

const initial_migration_name = "001_create_parking_schema"

fn table_exists(db: sqlight.Connection, table_name: String) -> Bool {
  let assert Ok(rows) =
    sqlight.query(
      "
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = ?;
      ",
      on: db,
      with: [sqlight.text(table_name)],
      expecting: decode.at([0], decode.string),
    )

  list.contains(rows, table_name)
}

fn migration_is_recorded(db: sqlight.Connection) -> Bool {
  let assert Ok(names) =
    sqlight.query(
      "
      SELECT name
      FROM __migrations
      WHERE name = ?;
      ",
      on: db,
      with: [sqlight.text(initial_migration_name)],
      expecting: decode.at([0], decode.string),
    )

  list.contains(names, initial_migration_name)
}

// MARK: New Database

pub fn migrate_creates_schema_for_new_database_test() {
  let assert Ok(db) = connection.connect_to(":memory:")

  let assert Ok(Nil) = migration.migrate(db, migrations_dir)

  table_exists(db, "parking_floors")
  |> should.be_true

  table_exists(db, "parking_slots")
  |> should.be_true

  table_exists(db, "vehicles")
  |> should.be_true

  table_exists(db, "parking_sessions")
  |> should.be_true

  table_exists(db, "parking_tickets")
  |> should.be_true

  table_exists(db, "__migrations")
  |> should.be_true

  migration_is_recorded(db)
  |> should.be_true

  let assert Ok(Nil) = sqlight.close(db)
}

// MARK: Legacy Database Adoption

pub fn migrate_adopts_existing_legacy_schema_test() {
  let assert Ok(db) = connection.connect_to(":memory:")

  let assert Ok(schema_sql) =
    simplifile.read("priv/repo/migrations/001_create_parking_schema.up.sql")

  let assert Ok(Nil) = sqlight.exec(schema_sql, on: db)

  let assert Ok(Nil) =
    sqlight.exec(
      "
      CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      INSERT INTO schema_migrations (version, name)
      VALUES (1, '001_create_parking_schema.sql');
      ",
      on: db,
    )

  let assert Ok(Nil) = migration.migrate(db, migrations_dir)
  let assert Ok(Nil) = migration.migrate(db, migrations_dir)

  table_exists(db, "parking_floors")
  |> should.be_true

  table_exists(db, "parking_slots")
  |> should.be_true

  table_exists(db, "vehicles")
  |> should.be_true

  table_exists(db, "parking_sessions")
  |> should.be_true

  table_exists(db, "parking_tickets")
  |> should.be_true

  migration_is_recorded(db)
  |> should.be_true

  let assert Ok(names) =
    sqlight.query(
      "
      SELECT name
      FROM __migrations
      WHERE name = ?;
      ",
      on: db,
      with: [sqlight.text(initial_migration_name)],
      expecting: decode.at([0], decode.string),
    )

  list.length(names)
  |> should.equal(1)

  let assert Ok(Nil) = sqlight.close(db)
}

// MARK: Partial Schema

pub fn migrate_rejects_partial_schema_test() {
  let assert Ok(db) = connection.connect_to(":memory:")

  let assert Ok(Nil) =
    sqlight.exec(
      "
      CREATE TABLE parking_floors (
        id TEXT PRIMARY KEY NOT NULL
      );
      ",
      on: db,
    )

  let assert Error(_) = migration.migrate(db, migrations_dir)

  table_exists(db, "parking_floors")
  |> should.be_true

  table_exists(db, "parking_slots")
  |> should.be_false

  let assert Ok(Nil) = sqlight.close(db)
}

// MARK: Idempotency

pub fn migrate_does_not_apply_existing_migration_twice_test() {
  let assert Ok(db) = connection.connect_to(":memory:")

  let assert Ok(Nil) = migration.migrate(db, migrations_dir)
  let assert Ok(Nil) = migration.migrate(db, migrations_dir)

  let assert Ok(names) =
    sqlight.query(
      "
      SELECT name
      FROM __migrations
      WHERE name = ?;
      ",
      on: db,
      with: [sqlight.text(initial_migration_name)],
      expecting: decode.at([0], decode.string),
    )

  list.length(names)
  |> should.equal(1)

  let assert Ok(Nil) = sqlight.close(db)
}

pub fn migrate_rejects_migration_history_without_domain_schema_test() {
  let assert Ok(db) = connection.connect_to(":memory:")

  let assert Ok(Nil) =
    sqlight.exec(
      "
      CREATE TABLE __migrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );

      INSERT INTO __migrations (name)
      VALUES ('001_create_parking_schema');
      ",
      on: db,
    )

  let assert Error(_) = migration.migrate(db, migrations_dir)

  table_exists(db, "parking_floors")
  |> should.be_false

  table_exists(db, "parking_slots")
  |> should.be_false

  let assert Ok(Nil) = sqlight.close(db)
}
