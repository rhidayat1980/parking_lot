import application/ports/parking_floor_repository
import application/ports/parking_session_repository
import application/ports/repository_error
import domain/floor
import domain/parking_session
import gleam/result

/// Data required to display the current parking lot status.
pub type ParkingStatus {
  ParkingStatus(
    floors: List(floor.ParkingFloor),
    active_sessions: List(parking_session.ParkingSession),
  )
}

/// Errors that can occur while retrieving the parking status.
pub type ViewParkingStatusError {
  FloorRepositoryFailed(repository_error.RepositoryError)
  SessionRepositoryFailed(repository_error.RepositoryError)
}

/// Retrieves all parking floors and currently active parking sessions.
pub fn view(
  floor_repository: parking_floor_repository.ParkingFloorRepository,
  session_repository: parking_session_repository.ParkingSessionRepository,
) -> Result(ParkingStatus, ViewParkingStatusError) {
  use floors <- result.try(
    floor_repository.get_all_floors()
    |> result.map_error(FloorRepositoryFailed),
  )

  use active_sessions <- result.try(
    session_repository.get_active_sessions()
    |> result.map_error(SessionRepositoryFailed),
  )

  Ok(ParkingStatus(floors: floors, active_sessions: active_sessions))
}
