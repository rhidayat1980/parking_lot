import domain/parking_allocation
import domain/parking_session
import domain/parking_slot
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

fn make_session_id(id: String) -> parking_session.ParkingSessionId {
  let assert Ok(session_id) = parking_session.new_parking_session_id(id)

  session_id
}

fn make_existing_session(
  session_id: String,
  parked_vehicle: vehicle.Vehicle,
  slot: parking_slot.ParkingSlot,
  entry_time: Int,
) -> parking_session.ParkingSession {
  let assert Ok(session) =
    parking_session.new_parking_session(
      make_session_id(session_id),
      vehicle.get_vehicle_id(parked_vehicle),
      parking_slot.get_parking_slot_id(slot),
      entry_time,
    )

  session
}

fn make_allocation_request(
  session_id: String,
  candidate_vehicle: vehicle.Vehicle,
  slot: parking_slot.ParkingSlot,
  entry_time: Int,
) -> parking_allocation.ParkingAllocationRequest {
  parking_allocation.ParkingAllocationRequest(
    session_id: make_session_id(session_id),
    vehicle: candidate_vehicle,
    slot: slot,
    entry_time: entry_time,
  )
}

// MARK: Successful Allocation

pub fn allocation_succeeds_when_vehicle_and_slot_are_available_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)

  let request = make_allocation_request("SESSION-001", car, slot, 1000)

  let result = parking_allocation.allocate_parking_session([], request)

  case result {
    Ok(session) -> {
      parking_session.get_parking_session_state(session)
      |> should.equal(parking_session.Active)

      parking_session.get_parking_session_vehicle_id(session)
      |> should.equal(vehicle.get_vehicle_id(car))

      parking_session.get_parking_session_slot_id(session)
      |> should.equal(parking_slot.get_parking_slot_id(slot))

      parking_session.get_parking_session_entry_time(session)
      |> should.equal(1000)
    }

    Error(_) -> should.fail()
  }
}

// MARK: Vehicle Already Parked

pub fn allocation_fails_when_vehicle_already_has_active_session_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let existing_slot = make_slot("SLOT-001", vehicle.Car)
  let target_slot = make_slot("SLOT-002", vehicle.Car)

  let existing_session =
    make_existing_session("SESSION-001", car, existing_slot, 1000)

  let request = make_allocation_request("SESSION-002", car, target_slot, 2000)

  parking_allocation.allocate_parking_session([existing_session], request)
  |> should.equal(Error(parking_allocation.VehicleAlreadyParked))
}

// MARK: Slot Already Occupied

pub fn allocation_fails_when_slot_is_occupied_test() {
  let existing_car = make_vehicle("VEHICLE-001", vehicle.Car)
  let new_car = make_vehicle("VEHICLE-002", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)

  let existing_session =
    make_existing_session("SESSION-001", existing_car, slot, 1000)

  let request = make_allocation_request("SESSION-002", new_car, slot, 2000)

  parking_allocation.allocate_parking_session([existing_session], request)
  |> should.equal(Error(parking_allocation.ParkingSlotOccupied))
}

// MARK: Vehicle Type Compatibility

pub fn allocation_fails_when_vehicle_type_is_not_supported_test() {
  let motorcycle = make_vehicle("VEHICLE-001", vehicle.Motorcycle)
  let car_slot = make_slot("SLOT-001", vehicle.Car)

  let request =
    make_allocation_request("SESSION-001", motorcycle, car_slot, 1000)

  parking_allocation.allocate_parking_session([], request)
  |> should.equal(Error(parking_allocation.VehicleTypeNotSupported))
}

// MARK: Invalid Entry Time

pub fn allocation_fails_when_entry_time_is_negative_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)

  let request = make_allocation_request("SESSION-001", car, slot, -1)

  parking_allocation.allocate_parking_session([], request)
  |> should.equal(Error(parking_allocation.InvalidEntryTime))
}

// MARK: Validation Priority

pub fn vehicle_type_error_takes_priority_over_availability_errors_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let motorcycle = make_vehicle("VEHICLE-002", vehicle.Motorcycle)
  let occupied_slot = make_slot("SLOT-001", vehicle.Car)

  let existing_session =
    make_existing_session("SESSION-001", car, occupied_slot, 1000)

  let request =
    make_allocation_request("SESSION-002", motorcycle, occupied_slot, 2000)

  parking_allocation.allocate_parking_session([existing_session], request)
  |> should.equal(Error(parking_allocation.VehicleTypeNotSupported))
}

// MARK: Reuse After Session Closure

pub fn vehicle_can_park_again_after_previous_session_is_closed_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)

  let existing_session = make_existing_session("SESSION-001", car, slot, 1000)

  let assert Ok(closed_session) =
    parking_session.close_parking_session(existing_session, 1500)

  let request = make_allocation_request("SESSION-002", car, slot, 2000)

  let result =
    parking_allocation.allocate_parking_session([closed_session], request)

  case result {
    Ok(session) ->
      parking_session.get_parking_session_state(session)
      |> should.equal(parking_session.Active)

    Error(_) -> should.fail()
  }
}

pub fn slot_can_be_reused_after_previous_session_is_closed_test() {
  let first_car = make_vehicle("VEHICLE-001", vehicle.Car)
  let second_car = make_vehicle("VEHICLE-002", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)

  let existing_session =
    make_existing_session("SESSION-001", first_car, slot, 1000)

  let assert Ok(closed_session) =
    parking_session.close_parking_session(existing_session, 1500)

  let request = make_allocation_request("SESSION-002", second_car, slot, 2000)

  let result =
    parking_allocation.allocate_parking_session([closed_session], request)

  case result {
    Ok(session) -> {
      parking_session.get_parking_session_vehicle_id(session)
      |> should.equal(vehicle.get_vehicle_id(second_car))

      parking_session.get_parking_session_slot_id(session)
      |> should.equal(parking_slot.get_parking_slot_id(slot))
    }

    Error(_) -> should.fail()
  }
}
