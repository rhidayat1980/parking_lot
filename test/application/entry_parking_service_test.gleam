import application/entry_parking
import application/entry_parking_service
import application/ports/entry_parking_transaction
import application/ports/repository_error
import domain/floor
import domain/parking_session
import domain/parking_slot
import domain/parking_ticket
import domain/vehicle
import gleeunit/should

// MARK: Test Helpers

fn make_vehicle(
  id: String,
  vehicle_type: vehicle.VehicleType,
) -> vehicle.Vehicle {
  let assert Ok(vehicle_id) = vehicle.new_vehicle_id(id)
  let assert Ok(plate_number) = vehicle.new_plate_number("B 1234 ABC")
  vehicle.new_vehicle(vehicle_id, plate_number, vehicle_type)
}

fn make_slot(
  id: String,
  supported_type: vehicle.VehicleType,
) -> parking_slot.ParkingSlot {
  let assert Ok(slot_id) = parking_slot.new_parking_slot_id(id)
  parking_slot.new_parking_slot(slot_id, supported_type)
}

fn make_floor(
  id: String,
  slots: List(parking_slot.ParkingSlot),
) -> floor.ParkingFloor {
  let assert Ok(floor_id) = floor.new_parking_floor_id(id)
  let initial_floor = floor.new_parking_floor(floor_id)
  add_slots(initial_floor, slots)
}

fn add_slots(
  current_floor: floor.ParkingFloor,
  slots: List(parking_slot.ParkingSlot),
) -> floor.ParkingFloor {
  case slots {
    [] -> current_floor
    [slot, ..remaining] -> {
      let assert Ok(updated_floor) = floor.add_parking_slot(current_floor, slot)
      add_slots(updated_floor, remaining)
    }
  }
}

fn make_session_id(id: String) -> parking_session.ParkingSessionId {
  let assert Ok(session_id) = parking_session.new_parking_session_id(id)
  session_id
}

fn make_ticket_id(id: String) -> parking_ticket.ParkingTicketId {
  let assert Ok(ticket_id) = parking_ticket.new_parking_ticket_id(id)
  ticket_id
}

fn make_request(
  session_id: String,
  ticket_id: String,
  candidate_vehicle: vehicle.Vehicle,
  entry_time: Int,
) -> entry_parking.EntryParkingRequest {
  entry_parking.EntryParkingRequest(
    session_id: make_session_id(session_id),
    ticket_id: make_ticket_id(ticket_id),
    vehicle: candidate_vehicle,
    entry_time: entry_time,
  )
}

fn make_service(
  floors: List(floor.ParkingFloor),
  sessions: List(parking_session.ParkingSession),
) -> entry_parking_service.EntryParkingService {
  let transaction =
    entry_parking_transaction.EntryParkingTransaction(enter: fn(request) {
      case entry_parking.enter_parking(floors, sessions, request) {
        Ok(entry_result) -> Ok(entry_result)
        Error(error) -> Error(entry_parking_transaction.EntryFailed(error))
      }
    })

  entry_parking_service.new(transaction)
}

fn make_storage_error() -> repository_error.RepositoryError {
  repository_error.WriteFailed("database unavailable")
}

fn make_failing_service(
  error: entry_parking_transaction.EntryParkingTransactionError,
) -> entry_parking_service.EntryParkingService {
  let transaction =
    entry_parking_transaction.EntryParkingTransaction(enter: fn(_) {
      Error(error)
    })

  entry_parking_service.new(transaction)
}

// MARK: Successful Entry

pub fn entry_succeeds_and_returns_entry_result_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)
  let parking_floor = make_floor("FLOOR-001", [slot])

  let service = make_service([parking_floor], [])
  let request = make_request("SESSION-001", "TICKET-001", car, 1000)

  let result = entry_parking_service.enter(service, request)

  case result {
    Ok(entry_result) -> {
      parking_slot.get_parking_slot_id(entry_result.slot)
      |> parking_slot.get_parking_slot_id_value
      |> should.equal("SLOT-001")

      parking_session.get_parking_session_state(entry_result.session)
      |> should.equal(parking_session.Active)

      parking_ticket.get_parking_ticket_issued_at(entry_result.ticket)
      |> should.equal(1000)

      parking_ticket.get_parking_ticket_session_id(entry_result.ticket)
      |> should.equal(make_session_id("SESSION-001"))
    }
    Error(_) -> should.fail()
  }
}

// MARK: Domain Failure

pub fn entry_fails_when_no_parking_slot_is_available_test() {
  let service = make_service([], [])

  let request =
    make_request(
      "SESSION-001",
      "TICKET-001",
      make_vehicle("VEHICLE-001", vehicle.Car),
      1000,
    )

  entry_parking_service.enter(service, request)
  |> should.equal(
    Error(entry_parking_service.EntryFailed(
      entry_parking.NoAvailableParkingSlot,
    )),
  )
}

// MARK: Repository Failure

pub fn entry_fails_when_transaction_repository_fails_test() {
  let service =
    make_failing_service(
      entry_parking_transaction.RepositoryFailed(make_storage_error()),
    )

  let request =
    make_request(
      "SESSION-001",
      "TICKET-001",
      make_vehicle("VEHICLE-001", vehicle.Car),
      1000,
    )

  entry_parking_service.enter(service, request)
  |> should.equal(
    Error(entry_parking_service.TransactionFailed(make_storage_error())),
  )
}

// MARK: Transaction Domain Failure

pub fn entry_fails_when_transaction_returns_domain_error_test() {
  let service =
    make_failing_service(entry_parking_transaction.EntryFailed(
      entry_parking.NoAvailableParkingSlot,
    ))

  let request =
    make_request(
      "SESSION-001",
      "TICKET-001",
      make_vehicle("VEHICLE-001", vehicle.Car),
      1000,
    )

  entry_parking_service.enter(service, request)
  |> should.equal(
    Error(entry_parking_service.EntryFailed(
      entry_parking.NoAvailableParkingSlot,
    )),
  )
}
