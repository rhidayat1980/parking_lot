import application/ports/repository_error
import domain/floor

// MARK: Parking Floor Repository

pub type ParkingFloorRepository {
  ParkingFloorRepository(
    get_all_floors: fn() ->
      Result(List(floor.ParkingFloor), repository_error.RepositoryError),
    save_floor: fn(floor.ParkingFloor) ->
      Result(Nil, repository_error.RepositoryError),
  )
}
