import application/ports/parking_session_repository
import application/ports/repository_error
import domain/parking_session
import domain/parking_slot
import domain/vehicle
import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/result
import sqlight

pub type SqliteSessionRepository {
  SqliteSessionRepository(db: sqlight.Connection)
}

pub fn new(db: sqlight.Connection) -> SqliteSessionRepository {
  SqliteSessionRepository(db: db)
}

pub fn to_port(
  repository: SqliteSessionRepository,
) -> parking_session_repository.ParkingSessionRepository {
  parking_session_repository.ParkingSessionRepository(
    get_active_sessions: fn() { get_active_sessions(repository) },
    get_session: fn(id) { get_session(repository, id) },
  )
}

// -----------------------------------------------------------------------------
// Repository
// -----------------------------------------------------------------------------

pub fn get_active_sessions(
  repository: SqliteSessionRepository,
) -> Result(
  List(parking_session.ParkingSession),
  repository_error.RepositoryError,
) {
  let SqliteSessionRepository(db: db) = repository

  use session_data <- result.try(load_active_sessions(db))

  build_sessions(session_data)
}

pub fn get_session(
  repository: SqliteSessionRepository,
  id: parking_session.ParkingSessionId,
) -> Result(
  option.Option(parking_session.ParkingSession),
  repository_error.RepositoryError,
) {
  let SqliteSessionRepository(db: db) = repository

  use session_data <- result.try(load_session(db, id))

  case session_data {
    [] -> Ok(option.None)

    [data] -> {
      use session <- result.try(build_session_from_data(data))
      Ok(option.Some(session))
    }

    [_, _, ..] ->
      Error(repository_error.StorageError(
        "Multiple parking sessions found for one session ID",
      ))
  }
}

// -----------------------------------------------------------------------------
// Database queries
// -----------------------------------------------------------------------------

fn load_active_sessions(
  db: sqlight.Connection,
) -> Result(
  List(#(String, String, String, Int)),
  repository_error.RepositoryError,
) {
  query(sqlight.query(
    "
    SELECT
      id,
      vehicle_id,
      slot_id,
      entry_time
    FROM parking_sessions
    WHERE state = 'Active'
    ORDER BY entry_time, id;
    ",
    on: db,
    with: [],
    expecting: active_session_decoder(),
  ))
}

fn load_session(
  db: sqlight.Connection,
  id: parking_session.ParkingSessionId,
) -> Result(
  List(#(String, String, String, Int, String, Int)),
  repository_error.RepositoryError,
) {
  query(sqlight.query(
    "
    SELECT
      id,
      vehicle_id,
      slot_id,
      entry_time,
      state,
      COALESCE(exit_time, -1)
    FROM parking_sessions
    WHERE id = ?;
    ",
    on: db,
    with: [
      sqlight.text(parking_session.get_parking_session_id_value(id)),
    ],
    expecting: session_decoder(),
  ))
}

fn active_session_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(session_id) {
    decode.at([1], decode.string)
    |> decode.then(fn(vehicle_id) {
      decode.at([2], decode.string)
      |> decode.then(fn(slot_id) {
        decode.at([3], decode.int)
        |> decode.map(fn(entry_time) {
          #(session_id, vehicle_id, slot_id, entry_time)
        })
      })
    })
  })
}

fn session_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(session_id) {
    decode.at([1], decode.string)
    |> decode.then(fn(vehicle_id) {
      decode.at([2], decode.string)
      |> decode.then(fn(slot_id) {
        decode.at([3], decode.int)
        |> decode.then(fn(entry_time) {
          decode.at([4], decode.string)
          |> decode.then(fn(state) {
            decode.at([5], decode.int)
            |> decode.map(fn(exit_time) {
              #(session_id, vehicle_id, slot_id, entry_time, state, exit_time)
            })
          })
        })
      })
    })
  })
}

// -----------------------------------------------------------------------------
// Database -> Domain conversion
// -----------------------------------------------------------------------------

fn build_sessions(
  session_data: List(#(String, String, String, Int)),
) -> Result(
  List(parking_session.ParkingSession),
  repository_error.RepositoryError,
) {
  list.fold(session_data, Ok([]), fn(acc, data) {
    use sessions <- result.try(acc)
    use session <- result.try(build_active_session_from_data(data))

    Ok(list.append(sessions, [session]))
  })
}

fn build_active_session_from_data(
  data: #(String, String, String, Int),
) -> Result(parking_session.ParkingSession, repository_error.RepositoryError) {
  let #(session_id, vehicle_id, slot_id, entry_time) = data

  build_session(session_id, vehicle_id, slot_id, entry_time)
}

fn build_session_from_data(
  data: #(String, String, String, Int, String, Int),
) -> Result(parking_session.ParkingSession, repository_error.RepositoryError) {
  let #(session_id, vehicle_id, slot_id, entry_time, state, exit_time) = data

  use session <- result.try(build_session(
    session_id,
    vehicle_id,
    slot_id,
    entry_time,
  ))

  case state {
    "Active" if exit_time == -1 -> Ok(session)

    "Closed" if exit_time >= 0 ->
      case parking_session.close_parking_session(session, exit_time) {
        Ok(closed_session) -> Ok(closed_session)

        Error(error) ->
          Error(
            repository_error.StorageError(parking_session.error_message(error)),
          )
      }

    _ ->
      Error(repository_error.StorageError(
        "Invalid parking session state or exit time in database",
      ))
  }
}

fn build_session(
  session_id: String,
  vehicle_id: String,
  slot_id: String,
  entry_time: Int,
) -> Result(parking_session.ParkingSession, repository_error.RepositoryError) {
  use id <- result.try(case parking_session.new_parking_session_id(session_id) {
    Ok(value) -> Ok(value)
    Error(error) ->
      Error(repository_error.StorageError(parking_session.error_message(error)))
  })

  use vehicle_id <- result.try(case vehicle.new_vehicle_id(vehicle_id) {
    Ok(value) -> Ok(value)
    Error(error) ->
      Error(repository_error.StorageError(vehicle.error_message(error)))
  })

  use slot_id <- result.try(case parking_slot.new_parking_slot_id(slot_id) {
    Ok(value) -> Ok(value)
    Error(error) ->
      Error(repository_error.StorageError(parking_slot.error_message(error)))
  })

  case
    parking_session.new_parking_session(id, vehicle_id, slot_id, entry_time)
  {
    Ok(session) -> Ok(session)

    Error(error) ->
      Error(repository_error.StorageError(parking_session.error_message(error)))
  }
}

// -----------------------------------------------------------------------------
// Error mapping
// -----------------------------------------------------------------------------

fn query(
  result: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case result {
    Ok(value) -> Ok(value)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.StorageError(message))
  }
}
