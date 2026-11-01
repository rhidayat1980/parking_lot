import application/exit_parking
import domain/parking_fee
import domain/parking_session
import domain/parking_slot
import domain/payment
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

fn make_payment_id() -> payment.PaymentId {
  let assert Ok(id) = payment.new_payment_id("PAYMENT-001")
  id
}

fn make_request(
  session: parking_session.ParkingSession,
  payment_id: option.Option(payment.PaymentId),
  exit_time: Int,
  hourly_rate: Int,
) -> exit_parking.ExitParkingRequest {
  exit_parking.ExitParkingRequest(
    session_id: parking_session.get_parking_session_id(session),
    payment_id: payment_id,
    exit_time: exit_time,
    hourly_rate: hourly_rate,
    payment_method: payment.Cash,
  )
}

// MARK: Zero Fee

pub fn zero_fee_closes_session_without_payment_test() {
  let session = make_parking_session()
  let request = make_request(session, None, 1000, 5000)

  let assert Ok(result) = exit_parking.exit_parking(session, request)

  should.equal(result.fee, 0)
  should.equal(result.duration_seconds, 0)
  should.equal(result.payment, None)
  should.equal(
    parking_session.get_parking_session_state(result.session),
    parking_session.Closed(1000),
  )
}

pub fn zero_fee_does_not_require_payment_id_test() {
  let session = make_parking_session()
  let request = make_request(session, None, 1000, 5000)

  should.be_ok(exit_parking.exit_parking(session, request))
}

// MARK: Successful Payment

pub fn positive_fee_creates_succeeded_payment_test() {
  let session = make_parking_session()
  let request = make_request(session, Some(make_payment_id()), 4600, 5000)

  let assert Ok(result) = exit_parking.exit_parking(session, request)

  should.equal(result.duration_seconds, 3600)
  should.equal(result.fee, 5000)

  case result.payment {
    None -> should.fail()
    Some(settled_payment) -> {
      should.equal(
        payment.get_payment_status(settled_payment),
        payment.Succeeded,
      )
      should.equal(payment.get_payment_amount(settled_payment), 5000)
      should.equal(payment.get_payment_method(settled_payment), payment.Cash)
    }
  }

  should.equal(
    parking_session.get_parking_session_state(result.session),
    parking_session.Closed(4600),
  )
}

pub fn positive_fee_requires_payment_id_test() {
  let session = make_parking_session()
  let request = make_request(session, None, 4600, 5000)

  should.equal(
    exit_parking.exit_parking(session, request),
    Error(exit_parking.MissingPaymentId),
  )
}

// MARK: Session Validation

pub fn closed_session_cannot_exit_again_test() {
  let session = make_parking_session()

  let assert Ok(closed_session) =
    parking_session.close_parking_session(session, 2000)

  let request =
    make_request(closed_session, Some(make_payment_id()), 3000, 5000)

  should.equal(
    exit_parking.exit_parking(closed_session, request),
    Error(exit_parking.SessionClosingFailed(
      parking_session.ParkingSessionAlreadyClosed,
    )),
  )
}

pub fn exit_before_entry_is_rejected_test() {
  let session = make_parking_session()
  let request = make_request(session, Some(make_payment_id()), 999, 5000)

  should.equal(
    exit_parking.exit_parking(session, request),
    Error(exit_parking.SessionClosingFailed(parking_session.InvalidExitTime)),
  )
}

// MARK: Fee Validation

pub fn invalid_hourly_rate_is_rejected_test() {
  let session = make_parking_session()
  let request = make_request(session, None, 2000, 0)

  should.equal(
    exit_parking.exit_parking(session, request),
    Error(exit_parking.FeeCalculationFailed(parking_fee.InvalidHourlyRate)),
  )
}

// MARK: Immutability

pub fn failed_exit_does_not_mutate_original_session_test() {
  let session = make_parking_session()
  let request = make_request(session, None, 4600, 5000)

  let assert Error(_) = exit_parking.exit_parking(session, request)

  should.equal(
    parking_session.get_parking_session_state(session),
    parking_session.Active,
  )
}
