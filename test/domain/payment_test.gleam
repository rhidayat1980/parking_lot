import domain/parking_session
import domain/payment
import gleeunit/should

// MARK: Test Helpers

fn create_payment() -> payment.Payment {
  let assert Ok(payment_id) = payment.new_payment_id("PAY-001")

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(new_payment) =
    payment.new_payment(payment_id, session_id, 15_000, payment.Cash, 1000)

  new_payment
}

// MARK: Payment ID

pub fn payment_id_rejects_empty_value_test() {
  should.equal(payment.new_payment_id(""), Error(payment.EmptyPaymentId))
}

pub fn payment_id_rejects_whitespace_test() {
  should.equal(payment.new_payment_id("   "), Error(payment.EmptyPaymentId))
}

pub fn payment_id_trims_whitespace_test() {
  let assert Ok(id) = payment.new_payment_id("  PAY-001  ")

  should.equal(payment.get_payment_id_value(id), "PAY-001")
}

pub fn payment_id_accessor_returns_payment_id_test() {
  let new_payment = create_payment()

  payment.get_payment_id(new_payment)
  |> payment.get_payment_id_value
  |> should.equal("PAY-001")
}

// MARK: Payment Construction

pub fn payment_rejects_zero_amount_test() {
  let assert Ok(id) = payment.new_payment_id("PAY-001")

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  should.equal(
    payment.new_payment(id, session_id, 0, payment.Cash, 1000),
    Error(payment.InvalidPaymentAmount),
  )
}

pub fn payment_rejects_negative_amount_test() {
  let assert Ok(id) = payment.new_payment_id("PAY-001")

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  should.equal(
    payment.new_payment(id, session_id, -1000, payment.Cash, 1000),
    Error(payment.InvalidPaymentAmount),
  )
}

pub fn new_payment_starts_pending_test() {
  let new_payment = create_payment()

  should.equal(payment.get_payment_status(new_payment), payment.Pending)
}

// MARK: Payment Accessors

pub fn payment_session_id_accessor_returns_session_id_test() {
  let new_payment = create_payment()

  let assert Ok(expected_session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  should.equal(payment.get_payment_session_id(new_payment), expected_session_id)
}

pub fn payment_amount_accessor_returns_amount_test() {
  let new_payment = create_payment()

  should.equal(payment.get_payment_amount(new_payment), 15_000)
}

pub fn payment_method_accessor_returns_method_test() {
  let new_payment = create_payment()

  should.equal(payment.get_payment_method(new_payment), payment.Cash)
}

pub fn payment_created_at_accessor_returns_timestamp_test() {
  let new_payment = create_payment()

  should.equal(payment.get_payment_created_at(new_payment), 1000)
}

// MARK: Payment Methods

pub fn payment_supports_qris_method_test() {
  let assert Ok(id) = payment.new_payment_id("PAY-QRIS")

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(new_payment) =
    payment.new_payment(id, session_id, 15_000, payment.Qris, 1000)

  should.equal(payment.get_payment_method(new_payment), payment.Qris)
}

pub fn payment_supports_debit_card_method_test() {
  let assert Ok(id) = payment.new_payment_id("PAY-DEBIT")

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(new_payment) =
    payment.new_payment(id, session_id, 15_000, payment.DebitCard, 1000)

  should.equal(payment.get_payment_method(new_payment), payment.DebitCard)
}

pub fn payment_supports_ewallet_method_test() {
  let assert Ok(id) = payment.new_payment_id("PAY-EWALLET")

  let assert Ok(session_id) =
    parking_session.new_parking_session_id("SESSION-001")

  let assert Ok(new_payment) =
    payment.new_payment(id, session_id, 15_000, payment.EWallet, 1000)

  should.equal(payment.get_payment_method(new_payment), payment.EWallet)
}

// MARK: Successful Transition

pub fn pending_payment_can_succeed_test() {
  let new_payment = create_payment()

  let assert Ok(succeeded_payment) = payment.succeed_payment(new_payment)

  should.equal(payment.get_payment_status(succeeded_payment), payment.Succeeded)
}

pub fn pending_payment_can_fail_test() {
  let new_payment = create_payment()

  let assert Ok(failed_payment) = payment.fail_payment(new_payment)

  should.equal(payment.get_payment_status(failed_payment), payment.Failed)
}

pub fn pending_payment_can_be_cancelled_test() {
  let new_payment = create_payment()

  let assert Ok(cancelled_payment) = payment.cancel_payment(new_payment)

  should.equal(payment.get_payment_status(cancelled_payment), payment.Cancelled)
}

// MARK: Finalized Payment

pub fn succeeded_payment_cannot_be_finalized_again_test() {
  let new_payment = create_payment()

  let assert Ok(succeeded_payment) = payment.succeed_payment(new_payment)

  should.equal(
    payment.fail_payment(succeeded_payment),
    Error(payment.PaymentAlreadyFinalized),
  )
}

pub fn failed_payment_cannot_be_finalized_again_test() {
  let new_payment = create_payment()

  let assert Ok(failed_payment) = payment.fail_payment(new_payment)

  should.equal(
    payment.succeed_payment(failed_payment),
    Error(payment.PaymentAlreadyFinalized),
  )
}

pub fn cancelled_payment_cannot_be_finalized_again_test() {
  let new_payment = create_payment()

  let assert Ok(cancelled_payment) = payment.cancel_payment(new_payment)

  should.equal(
    payment.succeed_payment(cancelled_payment),
    Error(payment.PaymentAlreadyFinalized),
  )
}

// MARK: Payment Immutability

pub fn payment_preserves_amount_after_success_test() {
  let new_payment = create_payment()

  let assert Ok(succeeded_payment) = payment.succeed_payment(new_payment)

  should.equal(payment.get_payment_amount(succeeded_payment), 15_000)
}

pub fn original_payment_remains_pending_after_success_test() {
  let original_payment = create_payment()

  let assert Ok(_succeeded_payment) = payment.succeed_payment(original_payment)

  should.equal(payment.get_payment_status(original_payment), payment.Pending)
}
