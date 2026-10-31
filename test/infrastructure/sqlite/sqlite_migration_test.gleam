import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import infrastructure/sqlite_connection as connection
import infrastructure/sqlite_migration as migration
import sqlight

pub fn adopt_existing_schema_records_initial_migration_test() {
  let assert Ok(Nil) = migration.adopt_existing_schema()
  let assert Ok(db) = connection.connect()

  let assert Ok(versions) =
    sqlight.query(
      "
      SELECT version
      FROM schema_migrations
      WHERE version = 1;
      ",
      on: db,
      with: [],
      expecting: decode.at([0], decode.int),
    )

  let assert Ok(Nil) = sqlight.close(db)

  versions
  |> list.contains(1)
  |> should.be_true
}

pub fn adopting_schema_twice_does_not_duplicate_migration_test() {
  let assert Ok(Nil) = migration.adopt_existing_schema()
  let assert Ok(Nil) = migration.adopt_existing_schema()

  let assert Ok(db) = connection.connect()

  let assert Ok(versions) =
    sqlight.query(
      "
      SELECT version
      FROM schema_migrations
      WHERE version = 1;
      ",
      on: db,
      with: [],
      expecting: decode.at([0], decode.int),
    )

  let assert Ok(Nil) = sqlight.close(db)

  versions
  |> list.length
  |> should.equal(1)
}
