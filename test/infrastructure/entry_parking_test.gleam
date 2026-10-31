import application/entry_parking
import domain/floor
import domain/parking_allocation
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
  let parking_floor = floor.new_parking_floor(floor_id)

  add_slots(parking_floor, slots)
}

fn add_slots(
  parking_floor: floor.ParkingFloor,
  slots: List(parking_slot.ParkingSlot),
) -> floor.ParkingFloor {
  case slots {
    [] -> parking_floor

    [slot, ..remaining_slots] -> {
      let assert Ok(updated_floor) = floor.add_parking_slot(parking_floor, slot)

      add_slots(updated_floor, remaining_slots)
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

// MARK: Successful Entry

pub fn entry_succeeds_when_compatible_slot_is_available_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)
  let parking_floor = make_floor("FLOOR-001", [slot])

  let request = make_request("SESSION-001", "TICKET-001", car, 1000)

  let result = entry_parking.enter_parking([parking_floor], [], request)

  case result {
    Ok(entry) -> {
      parking_slot.get_parking_slot_id(entry.slot)
      |> should.equal(parking_slot.get_parking_slot_id(slot))

      parking_session.get_parking_session_vehicle_id(entry.session)
      |> should.equal(vehicle.get_vehicle_id(car))

      parking_session.get_parking_session_state(entry.session)
      |> should.equal(parking_session.Active)

      parking_session.get_parking_session_entry_time(entry.session)
      |> should.equal(1000)

      parking_ticket.get_parking_ticket_session_id(entry.ticket)
      |> should.equal(make_session_id("SESSION-001"))

      parking_ticket.get_parking_ticket_issued_at(entry.ticket)
      |> should.equal(1000)
    }

    Error(_) -> should.fail()
  }
}

// MARK: Automatic Slot Selection

pub fn entry_skips_slot_with_incompatible_vehicle_type_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)

  let motorcycle_slot = make_slot("SLOT-001", vehicle.Motorcycle)
  let car_slot = make_slot("SLOT-002", vehicle.Car)

  let parking_floor = make_floor("FLOOR-001", [motorcycle_slot, car_slot])

  let request = make_request("SESSION-001", "TICKET-001", car, 1000)

  let result = entry_parking.enter_parking([parking_floor], [], request)

  case result {
    Ok(entry) ->
      parking_slot.get_parking_slot_id(entry.slot)
      |> should.equal(parking_slot.get_parking_slot_id(car_slot))

    Error(_) -> should.fail()
  }
}

pub fn entry_skips_occupied_slot_test() {
  let existing_car = make_vehicle("VEHICLE-001", vehicle.Car)
  let new_car = make_vehicle("VEHICLE-002", vehicle.Car)

  let occupied_slot = make_slot("SLOT-001", vehicle.Car)
  let available_slot = make_slot("SLOT-002", vehicle.Car)

  let parking_floor = make_floor("FLOOR-001", [occupied_slot, available_slot])

  let existing_session =
    make_existing_session("SESSION-001", existing_car, occupied_slot, 1000)

  let request = make_request("SESSION-002", "TICKET-002", new_car, 2000)

  let result =
    entry_parking.enter_parking([parking_floor], [existing_session], request)

  case result {
    Ok(entry) ->
      parking_slot.get_parking_slot_id(entry.slot)
      |> should.equal(parking_slot.get_parking_slot_id(available_slot))

    Error(_) -> should.fail()
  }
}

// MARK: Multiple Floors

pub fn entry_searches_next_floor_when_first_floor_has_no_available_slot_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)

  let first_slot = make_slot("SLOT-001", vehicle.Car)
  let second_slot = make_slot("SLOT-002", vehicle.Car)

  let first_floor = make_floor("FLOOR-001", [first_slot])
  let second_floor = make_floor("FLOOR-002", [second_slot])

  let existing_car = make_vehicle("VEHICLE-002", vehicle.Car)

  let existing_session =
    make_existing_session("SESSION-001", existing_car, first_slot, 1000)

  let request = make_request("SESSION-002", "TICKET-002", car, 2000)

  let result =
    entry_parking.enter_parking(
      [first_floor, second_floor],
      [existing_session],
      request,
    )

  case result {
    Ok(entry) -> {
      floor.get_parking_floor_id_value(entry.floor_id)
      |> should.equal("FLOOR-002")

      parking_slot.get_parking_slot_id(entry.slot)
      |> should.equal(parking_slot.get_parking_slot_id(second_slot))
    }

    Error(_) -> should.fail()
  }
}

// MARK: No Available Slot

pub fn entry_fails_when_no_floors_are_available_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)

  let request = make_request("SESSION-001", "TICKET-001", car, 1000)

  entry_parking.enter_parking([], [], request)
  |> should.equal(Error(entry_parking.NoAvailableParkingSlot))
}

pub fn entry_fails_when_all_slots_are_occupied_test() {
  let existing_car = make_vehicle("VEHICLE-001", vehicle.Car)
  let new_car = make_vehicle("VEHICLE-002", vehicle.Car)

  let slot = make_slot("SLOT-001", vehicle.Car)
  let parking_floor = make_floor("FLOOR-001", [slot])

  let existing_session =
    make_existing_session("SESSION-001", existing_car, slot, 1000)

  let request = make_request("SESSION-002", "TICKET-002", new_car, 2000)

  entry_parking.enter_parking([parking_floor], [existing_session], request)
  |> should.equal(Error(entry_parking.NoAvailableParkingSlot))
}

// MARK: Vehicle Already Parked

pub fn entry_fails_when_vehicle_already_has_active_session_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)

  let existing_slot = make_slot("SLOT-001", vehicle.Car)
  let available_slot = make_slot("SLOT-002", vehicle.Car)

  let parking_floor = make_floor("FLOOR-001", [available_slot])

  let existing_session =
    make_existing_session("SESSION-001", car, existing_slot, 1000)

  let request = make_request("SESSION-002", "TICKET-002", car, 2000)

  entry_parking.enter_parking([parking_floor], [existing_session], request)
  |> should.equal(
    Error(entry_parking.AllocationFailed(
      parking_allocation.VehicleAlreadyParked,
    )),
  )
}

// MARK: Invalid Entry Time

pub fn entry_fails_when_entry_time_is_negative_test() {
  let car = make_vehicle("VEHICLE-001", vehicle.Car)
  let slot = make_slot("SLOT-001", vehicle.Car)
  let parking_floor = make_floor("FLOOR-001", [slot])

  let request = make_request("SESSION-001", "TICKET-001", car, -1)

  entry_parking.enter_parking([parking_floor], [], request)
  |> should.equal(
    Error(entry_parking.AllocationFailed(parking_allocation.InvalidEntryTime)),
  )
}
