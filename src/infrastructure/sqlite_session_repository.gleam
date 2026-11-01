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

// -----------------------------------------------------------------------------
// Persistence model
// -----------------------------------------------------------------------------

type SessionRow {
  SessionRow(
    id: String,
    vehicle_id: String,
    slot_id: String,
    entry_time: Int,
    state: String,
    exit_time: Int,
  )
}

// -----------------------------------------------------------------------------
// Constructor
// -----------------------------------------------------------------------------

pub fn new(db: sqlight.Connection) -> SqliteSessionRepository {
  SqliteSessionRepository(db: db)
}

// -----------------------------------------------------------------------------
// Port adapter
// -----------------------------------------------------------------------------

pub fn to_port(
  repository: SqliteSessionRepository,
) -> parking_session_repository.ParkingSessionRepository {
  parking_session_repository.ParkingSessionRepository(
    get_active_sessions: fn() { get_active_sessions(repository) },
    get_session: fn(id) { get_session(repository, id) },
  )
}

// -----------------------------------------------------------------------------
// Repository operations
// -----------------------------------------------------------------------------

pub fn get_active_sessions(
  repository: SqliteSessionRepository,
) -> Result(
  List(parking_session.ParkingSession),
  repository_error.RepositoryError,
) {
  let SqliteSessionRepository(db: db) = repository

  use rows <- result.try(load_active_sessions(db))
  build_sessions(rows)
}

pub fn get_session(
  repository: SqliteSessionRepository,
  id: parking_session.ParkingSessionId,
) -> Result(
  option.Option(parking_session.ParkingSession),
  repository_error.RepositoryError,
) {
  let SqliteSessionRepository(db: db) = repository

  use rows <- result.try(load_session(db, id))

  case rows {
    [] -> Ok(option.None)

    [row] -> {
      use session <- result.try(session_row_to_domain(row))
      Ok(option.Some(session))
    }

    [_, _, ..] ->
      Error(repository_error.InvalidPersistedData(
        "Multiple parking sessions found for one session ID",
      ))
  }
}

// -----------------------------------------------------------------------------
// Database queries
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// Error mapping
// -----------------------------------------------------------------------------

fn read_query(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(result) -> Ok(result)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.ReadFailed(message))
  }
}

fn load_active_sessions(
  db: sqlight.Connection,
) -> Result(List(SessionRow), repository_error.RepositoryError) {
  read_query(sqlight.query(
    "
      SELECT
        id,
        vehicle_id,
        slot_id,
        entry_time,
        state,
        COALESCE(exit_time, -1)
      FROM parking_sessions
      WHERE state = 'Active'
      ORDER BY entry_time, id;
      ",
    on: db,
    with: [],
    expecting: session_row_decoder(),
  ))
}

fn load_session(
  db: sqlight.Connection,
  id: parking_session.ParkingSessionId,
) -> Result(List(SessionRow), repository_error.RepositoryError) {
  read_query(sqlight.query(
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
    expecting: session_row_decoder(),
  ))
}

// -----------------------------------------------------------------------------
// Persistence decoder
// -----------------------------------------------------------------------------

fn session_row_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(id) {
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
              SessionRow(
                id: id,
                vehicle_id: vehicle_id,
                slot_id: slot_id,
                entry_time: entry_time,
                state: state,
                exit_time: exit_time,
              )
            })
          })
        })
      })
    })
  })
}

// -----------------------------------------------------------------------------
// Persistence -> Domain mapping
// -----------------------------------------------------------------------------

fn build_sessions(
  rows: List(SessionRow),
) -> Result(
  List(parking_session.ParkingSession),
  repository_error.RepositoryError,
) {
  list.fold(rows, Ok([]), fn(acc, row) {
    use sessions <- result.try(acc)
    use session <- result.try(session_row_to_domain(row))

    Ok(list.append(sessions, [session]))
  })
}

fn session_row_to_domain(
  row: SessionRow,
) -> Result(parking_session.ParkingSession, repository_error.RepositoryError) {
  let SessionRow(
    id: session_id,
    vehicle_id: vehicle_id,
    slot_id: slot_id,
    entry_time: entry_time,
    state: state,
    exit_time: exit_time,
  ) = row

  use id <- result.try(restore_session_id(session_id))
  use vehicle_id <- result.try(restore_vehicle_id(vehicle_id))
  use slot_id <- result.try(restore_slot_id(slot_id))
  use session <- result.try(restore_session(id, vehicle_id, slot_id, entry_time))

  restore_session_state(session, state, exit_time)
}

// -----------------------------------------------------------------------------
// Domain value restoration
// -----------------------------------------------------------------------------

fn restore_session_id(
  value: String,
) -> Result(parking_session.ParkingSessionId, repository_error.RepositoryError) {
  case parking_session.new_parking_session_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(
        repository_error.InvalidPersistedData(parking_session.error_message(
          error,
        )),
      )
  }
}

fn restore_vehicle_id(
  value: String,
) -> Result(vehicle.VehicleId, repository_error.RepositoryError) {
  case vehicle.new_vehicle_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(repository_error.InvalidPersistedData(vehicle.error_message(error)))
  }
}

fn restore_slot_id(
  value: String,
) -> Result(parking_slot.ParkingSlotId, repository_error.RepositoryError) {
  case parking_slot.new_parking_slot_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(
        repository_error.InvalidPersistedData(parking_slot.error_message(error)),
      )
  }
}

// -----------------------------------------------------------------------------
// Domain entity restoration
// -----------------------------------------------------------------------------

fn restore_session(
  id: parking_session.ParkingSessionId,
  vehicle_id: vehicle.VehicleId,
  slot_id: parking_slot.ParkingSlotId,
  entry_time: Int,
) -> Result(parking_session.ParkingSession, repository_error.RepositoryError) {
  case
    parking_session.new_parking_session(id, vehicle_id, slot_id, entry_time)
  {
    Ok(session) -> Ok(session)

    Error(error) ->
      Error(
        repository_error.InvalidPersistedData(parking_session.error_message(
          error,
        )),
      )
  }
}

// -----------------------------------------------------------------------------
// Domain state restoration
// -----------------------------------------------------------------------------

fn restore_session_state(
  session: parking_session.ParkingSession,
  state: String,
  exit_time: Int,
) -> Result(parking_session.ParkingSession, repository_error.RepositoryError) {
  case state {
    "Active" if exit_time == -1 -> Ok(session)

    "Closed" if exit_time >= 0 ->
      case parking_session.close_parking_session(session, exit_time) {
        Ok(closed_session) -> Ok(closed_session)

        Error(error) ->
          Error(
            repository_error.InvalidPersistedData(parking_session.error_message(
              error,
            )),
          )
      }

    _ ->
      Error(repository_error.InvalidPersistedData(
        "Invalid parking session state or exit time in database",
      ))
  }
}
