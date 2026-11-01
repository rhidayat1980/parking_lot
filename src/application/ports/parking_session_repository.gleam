import application/ports/repository_error
import domain/parking_session
import gleam/option

// MARK: Parking Session Repository

pub type ParkingSessionRepository {
  ParkingSessionRepository(
    get_active_sessions: fn() ->
      Result(
        List(parking_session.ParkingSession),
        repository_error.RepositoryError,
      ),
    get_session: fn(parking_session.ParkingSessionId) ->
      Result(
        option.Option(parking_session.ParkingSession),
        repository_error.RepositoryError,
      ),
  )
}
