import domain/parking_session
import gleam/string

// MARK: Errors

pub type PaymentError {
  EmptyPaymentId
  InvalidPaymentAmount
  PaymentAlreadyFinalized
}

pub fn error_message(error: PaymentError) -> String {
  case error {
    EmptyPaymentId -> "Payment ID cannot be empty"
    InvalidPaymentAmount -> "Payment amount must be greater than zero"
    PaymentAlreadyFinalized -> "Payment has already been finalized"
  }
}

// MARK: Payment ID

pub opaque type PaymentId {
  PaymentId(String)
}

pub fn new_payment_id(value: String) -> Result(PaymentId, PaymentError) {
  let trimmed = string.trim(value)

  case trimmed {
    "" -> Error(EmptyPaymentId)
    _ -> Ok(PaymentId(trimmed))
  }
}

pub fn get_payment_id_value(id: PaymentId) -> String {
  let PaymentId(value) = id
  value
}

// MARK: Payment Method

pub type PaymentMethod {
  Cash
  Qris
  DebitCard
  EWallet
}

// MARK: Payment Status

pub type PaymentStatus {
  Pending
  Succeeded
  Failed
  Cancelled
}

// MARK: Payment

pub opaque type Payment {
  Payment(
    id: PaymentId,
    session_id: parking_session.ParkingSessionId,
    amount: Int,
    method: PaymentMethod,
    status: PaymentStatus,
    created_at: Int,
  )
}

// MARK: Constructor

pub fn new_payment(
  id: PaymentId,
  session_id: parking_session.ParkingSessionId,
  amount: Int,
  method: PaymentMethod,
  created_at: Int,
) -> Result(Payment, PaymentError) {
  case amount > 0 {
    True ->
      Ok(Payment(
        id: id,
        session_id: session_id,
        amount: amount,
        method: method,
        status: Pending,
        created_at: created_at,
      ))

    False -> Error(InvalidPaymentAmount)
  }
}

// MARK: Accessors

pub fn get_payment_id(payment: Payment) -> PaymentId {
  let Payment(id: id, ..) = payment
  id
}

pub fn get_payment_session_id(
  payment: Payment,
) -> parking_session.ParkingSessionId {
  let Payment(session_id: session_id, ..) = payment
  session_id
}

pub fn get_payment_amount(payment: Payment) -> Int {
  let Payment(amount: amount, ..) = payment
  amount
}

pub fn get_payment_method(payment: Payment) -> PaymentMethod {
  let Payment(method: method, ..) = payment
  method
}

pub fn get_payment_status(payment: Payment) -> PaymentStatus {
  let Payment(status: status, ..) = payment
  status
}

pub fn get_payment_created_at(payment: Payment) -> Int {
  let Payment(created_at: created_at, ..) = payment
  created_at
}

// MARK: State Transitions

pub fn succeed_payment(payment: Payment) -> Result(Payment, PaymentError) {
  transition_to(payment, Succeeded)
}

pub fn fail_payment(payment: Payment) -> Result(Payment, PaymentError) {
  transition_to(payment, Failed)
}

pub fn cancel_payment(payment: Payment) -> Result(Payment, PaymentError) {
  transition_to(payment, Cancelled)
}

fn transition_to(
  payment: Payment,
  new_status: PaymentStatus,
) -> Result(Payment, PaymentError) {
  case payment.status {
    Pending -> Ok(Payment(..payment, status: new_status))

    Succeeded | Failed | Cancelled -> Error(PaymentAlreadyFinalized)
  }
}
