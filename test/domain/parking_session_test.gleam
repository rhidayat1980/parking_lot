import domain/parking_session
import domain/parking_slot
import domain/vehicle
import gleam/option.{None, Some}
import gleeunit/should

// MARK: Test Helpers

fn make_parking_session() -> parking_session.ParkingSession {
  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(vehicle_id) = vehicle.new_vehicle_id("VEHICLE-001")

  let assert Ok(slot_id) = parking_slot.new_parking_slot_id("SLOT-001")

  let assert Ok(session) =
    parking_session.new_parking_session(session_id, vehicle_id, slot_id, 1000)

  session
}

// MARK: Parking Session ID

pub fn session_id_rejects_empty_value_test() {
  should.equal(
    parking_session.new_parking_session_id(""),
    Error(parking_session.EmptyParkingSessionId),
  )
}

pub fn session_id_rejects_whitespace_test() {
  should.equal(
    parking_session.new_parking_session_id("   "),
    Error(parking_session.EmptyParkingSessionId),
  )
}

pub fn session_id_trims_whitespace_test() {
  let assert Ok(id) = parking_session.new_parking_session_id("  SESSION-001  ")

  should.equal(parking_session.get_parking_session_id_value(id), "SESSION-001")
}

// MARK: Initial State

pub fn new_session_starts_active_test() {
  let session = make_parking_session()

  should.equal(
    parking_session.get_parking_session_state(session),
    parking_session.Active,
  )
}

pub fn new_session_has_no_exit_time_test() {
  let session = make_parking_session()

  should.equal(parking_session.get_parking_session_exit_time(session), None)
}

pub fn new_session_preserves_entry_time_test() {
  let session = make_parking_session()

  should.equal(parking_session.get_parking_session_entry_time(session), 1000)
}

// MARK: Close Parking Session

pub fn active_session_can_be_closed_test() {
  let session = make_parking_session()

  let assert Ok(closed_session) =
    parking_session.close_parking_session(session, 2000)

  should.equal(
    parking_session.get_parking_session_state(closed_session),
    parking_session.Closed(2000),
  )

  should.equal(
    parking_session.get_parking_session_exit_time(closed_session),
    Some(2000),
  )
}

pub fn session_rejects_exit_before_entry_test() {
  let session = make_parking_session()

  should.equal(
    parking_session.close_parking_session(session, 999),
    Error(parking_session.InvalidExitTime),
  )
}

pub fn closed_session_cannot_be_closed_again_test() {
  let session = make_parking_session()

  let assert Ok(closed_session) =
    parking_session.close_parking_session(session, 2000)

  should.equal(
    parking_session.close_parking_session(closed_session, 3000),
    Error(parking_session.ParkingSessionAlreadyClosed),
  )
}

// MARK: Identity and Immutability

pub fn closing_session_preserves_identity_and_entry_time_test() {
  let session = make_parking_session()

  let assert Ok(closed_session) =
    parking_session.close_parking_session(session, 2000)

  should.equal(
    parking_session.get_parking_session_id_value(
      parking_session.get_parking_session_id(closed_session),
    ),
    "SESSION-001",
  )

  should.equal(
    parking_session.get_parking_session_entry_time(closed_session),
    1000,
  )
}

pub fn closing_session_does_not_mutate_original_test() {
  let session = make_parking_session()

  let assert Ok(closed_session) =
    parking_session.close_parking_session(session, 2000)

  should.equal(
    parking_session.get_parking_session_state(session),
    parking_session.Active,
  )

  should.equal(
    parking_session.get_parking_session_state(closed_session),
    parking_session.Closed(2000),
  )
}

// MARK: Entry and Exit Time Boundaries

pub fn negative_entry_time_is_rejected_test() {
  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(vehicle_id) = vehicle.new_vehicle_id("VEHICLE-001")

  let assert Ok(slot_id) = parking_slot.new_parking_slot_id("SLOT-001")

  should.equal(
    parking_session.new_parking_session(session_id, vehicle_id, slot_id, -1),
    Error(parking_session.InvalidEntryTime),
  )
}

pub fn zero_entry_time_is_accepted_test() {
  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(vehicle_id) = vehicle.new_vehicle_id("VEHICLE-001")

  let assert Ok(slot_id) = parking_slot.new_parking_slot_id("SLOT-001")

  let assert Ok(session) =
    parking_session.new_parking_session(session_id, vehicle_id, slot_id, 0)

  should.equal(
    parking_session.get_parking_session_state(session),
    parking_session.Active,
  )

  should.equal(parking_session.get_parking_session_entry_time(session), 0)
}

pub fn exit_time_equal_to_entry_time_is_accepted_test() {
  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(vehicle_id) = vehicle.new_vehicle_id("VEHICLE-001")

  let assert Ok(slot_id) = parking_slot.new_parking_slot_id("SLOT-001")

  let assert Ok(session) =
    parking_session.new_parking_session(session_id, vehicle_id, slot_id, 1000)

  let assert Ok(closed_session) =
    parking_session.close_parking_session(session, 1000)

  should.equal(
    parking_session.get_parking_session_state(closed_session),
    parking_session.Closed(1000),
  )
}
