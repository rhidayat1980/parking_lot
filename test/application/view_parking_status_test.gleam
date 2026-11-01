// import application/ports/parking_floor_repository
// import application/ports/parking_session_repository
// import application/ports/repository_error
// import application/view_parking_status
// import domain/floor
// import domain/parking_session
// import domain/parking_slot
// import domain/vehicle
// import gleeunit
// import gleeunit/should

// pub fn main() {
//   gleeunit.main()
// }

// fn sample_floor_test() -> floor.ParkingFloor {
//   let floor_id = floor.new_parking_floor_id()
//   floor.new_parking_floor(floor_id)
// }

// fn sample_session_test() -> parking_session.ParkingSession {
//   let session_id = parking_session.new_parking_session_id()
//   let vehicle_id = vehicle.new_vehicle_id()
//   let slot_id = parking_slot.new_parking_slot_id()

//   parking_session.new_parking_session(session_id, vehicle_id, slot_id, 1)
// }

// pub fn view_returns_parking_status_when_both_repositories_succeed_test() {
//   let expected_floors = [sample_floor_test()]
//   let expected_sessions = [sample_session_test()]

//   let floor_repository =
//     parking_floor_repository.ParkingFloorRepository(get_all_floors: fn() {
//       Ok(expected_floors)
//     })

//   let session_repository =
//     parking_session_repository.ParkingSessionRepository(
//       get_active_sessions: fn() { Ok(expected_sessions) },
//     )

//   let result = view_parking_status.view(floor_repository, session_repository)

//   result
//   |> should.equal(
//     Ok(view_parking_status.ParkingStatus(
//       floors: expected_floors,
//       active_sessions: expected_sessions,
//     )),
//   )
// }

// pub fn view_returns_floor_repository_error_when_loading_floors_fails_test() {
//   let empty_sessions: List(parking_session.ParkingSession) = []

//   let floor_repository =
//     parking_floor_repository.ParkingFloorRepository(get_all_floors: fn() {
//       Error(repository_error.DatabaseError)
//     })

//   let session_repository =
//     parking_session_repository.ParkingSessionRepository(
//       get_active_sessions: fn() { Ok(empty_sessions) },
//     )

//   let result = view_parking_status.view(floor_repository, session_repository)

//   result
//   |> should.equal(
//     Error(view_parking_status.FloorRepositoryFailed(
//       repository_error.DatabaseError,
//     )),
//   )
// }

// pub fn view_returns_session_repository_error_when_loading_sessions_fails_test() {
//   let expected_floors = [sample_floor_test()]

//   let floor_repository =
//     parking_floor_repository.ParkingFloorRepository(get_all_floors: fn() {
//       Ok(expected_floors)
//     })

//   let session_repository =
//     parking_session_repository.ParkingSessionRepository(
//       get_active_sessions: fn() { Error(repository_error.DatabaseError) },
//     )

//   let result = view_parking_status.view(floor_repository, session_repository)

//   result
//   |> should.equal(
//     Error(view_parking_status.SessionRepositoryFailed(
//       repository_error.DatabaseError,
//     )),
//   )
// }
