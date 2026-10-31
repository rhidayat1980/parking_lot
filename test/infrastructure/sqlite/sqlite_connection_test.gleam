import gleeunit/should
import infrastructure/sqlite_connection as connection
import sqlight

pub fn connect_opens_database_test() {
  let assert Ok(db) = connection.connect()

  let assert Ok(_) = sqlight.exec("SELECT 1;", on: db)

  let assert Ok(Nil) = sqlight.close(db)

  should.be_ok(Ok(Nil))
}

pub fn foreign_keys_are_enabled_test() {
  let assert Ok(db) = connection.connect()

  let assert Ok(_) =
    sqlight.exec(
      "CREATE TABLE IF NOT EXISTS connection_test_parent (
        id INTEGER PRIMARY KEY
      );",
      on: db,
    )

  let assert Ok(_) =
    sqlight.exec(
      "CREATE TABLE IF NOT EXISTS connection_test_child (
        parent_id INTEGER NOT NULL,
        FOREIGN KEY (parent_id)
          REFERENCES connection_test_parent(id)
      );",
      on: db,
    )

  let result =
    sqlight.exec(
      "INSERT INTO connection_test_child (parent_id) VALUES (999999);",
      on: db,
    )

  let assert Error(_) = result

  let assert Ok(Nil) = sqlight.exec("DROP TABLE connection_test_child;", on: db)

  let assert Ok(Nil) =
    sqlight.exec("DROP TABLE connection_test_parent;", on: db)

  let assert Ok(Nil) = sqlight.close(db)
}
