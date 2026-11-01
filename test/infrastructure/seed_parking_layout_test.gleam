import application/seed_parking_layout
import domain/floor
import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import infrastructure/sqlite_connection
import infrastructure/sqlite_floor_repository
import simplifile
import sqlight

fn setup_database() -> sqlight.Connection {
  let assert Ok(db) = sqlite_connection.connect_to(":memory:")

  let assert Ok(migration_sql) =
    simplifile.read(
      from: "priv/repo/migrations/001_create_parking_schema.up.sql",
    )

  let assert Ok(Nil) = sqlight.exec(migration_sql, on: db)

  db
}

fn count_rows(db: sqlight.Connection, table: String) -> Int {
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) FROM " <> table <> ";",
      on: db,
      with: [],
      expecting: decode.field(0, decode.int, fn(value) { decode.success(value) }),
    )

  count
}

fn close_database(db: sqlight.Connection) -> Nil {
  let assert Ok(Nil) = sqlight.close(db)
  Nil
}

// -----------------------------------------------------------------------------
// Initial seeding
// -----------------------------------------------------------------------------

pub fn seed_parking_layout_creates_expected_layout_test() {
  let db = setup_database()

  let repository =
    sqlite_floor_repository.new(db)
    |> sqlite_floor_repository.to_port

  seed_parking_layout.seed(repository)
  |> should.equal(Ok(Nil))

  count_rows(db, "parking_floors")
  |> should.equal(2)

  count_rows(db, "parking_slots")
  |> should.equal(8)

  close_database(db)
}

// -----------------------------------------------------------------------------
// Idempotency
// -----------------------------------------------------------------------------

pub fn seed_parking_layout_is_idempotent_test() {
  let db = setup_database()

  let repository =
    sqlite_floor_repository.new(db)
    |> sqlite_floor_repository.to_port

  seed_parking_layout.seed(repository)
  |> should.equal(Ok(Nil))

  seed_parking_layout.seed(repository)
  |> should.equal(Ok(Nil))

  count_rows(db, "parking_floors")
  |> should.equal(2)

  count_rows(db, "parking_slots")
  |> should.equal(8)

  close_database(db)
}

// -----------------------------------------------------------------------------
// Domain reconstruction
// -----------------------------------------------------------------------------

pub fn seed_parking_layout_can_be_loaded_as_domain_aggregates_test() {
  let db = setup_database()
  let sqlite_repository = sqlite_floor_repository.new(db)

  let repository =
    sqlite_repository
    |> sqlite_floor_repository.to_port

  let assert Ok(Nil) = seed_parking_layout.seed(repository)

  let assert Ok(floors) =
    sqlite_floor_repository.get_all_floors(sqlite_repository)

  list.length(floors)
  |> should.equal(2)

  let slot_counts = list.map(floors, floor.get_parking_floor_slot_count)

  slot_counts
  |> should.equal([5, 3])

  close_database(db)
}
