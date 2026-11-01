import domain/parking_fee
import domain/parking_session
import domain/payment
import gleam/option
import gleam/result

// MARK: Errors

pub type ExitParkingError {
  SessionNotFound
  SessionClosingFailed(parking_session.ParkingSessionError)
  FeeCalculationFailed(parking_fee.ParkingFeeError)
  MissingPaymentId
  PaymentCreationFailed(payment.PaymentError)
  PaymentSettlementFailed(payment.PaymentError)
}

pub fn error_message(error: ExitParkingError) -> String {
  case error {
    SessionNotFound -> "Parking session was not found"

    SessionClosingFailed(session_error) ->
      parking_session.error_message(session_error)

    FeeCalculationFailed(fee_error) -> parking_fee.error_message(fee_error)

    MissingPaymentId ->
      "Payment ID is required when parking fee is greater than zero"

    PaymentCreationFailed(payment_error) -> payment.error_message(payment_error)

    PaymentSettlementFailed(payment_error) ->
      payment.error_message(payment_error)
  }
}

// MARK: Exit Parking Request

pub type ExitParkingRequest {
  ExitParkingRequest(
    session_id: parking_session.ParkingSessionId,
    payment_id: option.Option(payment.PaymentId),
    exit_time: Int,
    hourly_rate: Int,
    payment_method: payment.PaymentMethod,
  )
}

// MARK: Exit Parking Result

pub type ExitParkingResult {
  ExitParkingResult(
    session: parking_session.ParkingSession,
    payment: option.Option(payment.Payment),
    duration_seconds: Int,
    fee: Int,
  )
}

// MARK: Exit Parking

pub fn exit_parking(
  session: parking_session.ParkingSession,
  request: ExitParkingRequest,
) -> Result(ExitParkingResult, ExitParkingError) {
  let ExitParkingRequest(
    session_id: _,
    payment_id: payment_id,
    exit_time: exit_time,
    hourly_rate: hourly_rate,
    payment_method: payment_method,
  ) = request

  // Validate the session state and exit time first.
  use closed_session <- result.try(
    parking_session.close_parking_session(session, exit_time)
    |> result.map_error(SessionClosingFailed),
  )

  // Calculate the actual parking duration.
  let entry_time = parking_session.get_parking_session_entry_time(session)
  let duration_seconds = exit_time - entry_time

  // Calculate the parking fee.
  use fee <- result.try(
    parking_fee.calculate_parking_fee(duration_seconds, hourly_rate)
    |> result.map_error(FeeCalculationFailed),
  )

  // No payment is necessary when the fee is zero.
  case fee {
    0 ->
      Ok(ExitParkingResult(
        session: closed_session,
        payment: option.None,
        duration_seconds: duration_seconds,
        fee: fee,
      ))

    _ -> {
      // A positive fee requires a payment ID.
      use payment_id <- result.try(require_payment_id(payment_id))

      // Create a pending payment.
      use pending_payment <- result.try(
        payment.new_payment(
          payment_id,
          parking_session.get_parking_session_id(session),
          fee,
          payment_method,
          exit_time,
        )
        |> result.map_error(PaymentCreationFailed),
      )

      // Simulate successful payment settlement.
      use settled_payment <- result.try(
        payment.succeed_payment(pending_payment)
        |> result.map_error(PaymentSettlementFailed),
      )

      Ok(ExitParkingResult(
        session: closed_session,
        payment: option.Some(settled_payment),
        duration_seconds: duration_seconds,
        fee: fee,
      ))
    }
  }
}

// MARK: Payment ID Validation

fn require_payment_id(
  payment_id: option.Option(payment.PaymentId),
) -> Result(payment.PaymentId, ExitParkingError) {
  case payment_id {
    option.Some(id) -> Ok(id)
    option.None -> Error(MissingPaymentId)
  }
}
