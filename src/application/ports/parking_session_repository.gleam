import application/ports/repository_error
import domain/parking_session

// MARK: Parking Session Repository

pub type ParkingSessionRepository {
  ParkingSessionRepository(
    get_active_sessions: fn() ->
      Result(
        List(parking_session.ParkingSession),
        repository_error.RepositoryError,
      ),
  )
}
