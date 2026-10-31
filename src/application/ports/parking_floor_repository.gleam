import application/ports/repository_error
import domain/floor

// MARK: Parking Floor Repository

pub type ParkingFloorRepository {
  ParkingFloorRepository(
    get_all_floors: fn() ->
      Result(List(floor.ParkingFloor), repository_error.RepositoryError),
  )
}
