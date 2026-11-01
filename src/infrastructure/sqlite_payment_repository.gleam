import application/ports/payment_repository
import application/ports/repository_error
import domain/parking_session
import domain/payment
import gleam/dynamic/decode
import gleam/option
import gleam/result
import sqlight

pub type SqlitePaymentRepository {
  SqlitePaymentRepository(db: sqlight.Connection)
}

pub fn new(db: sqlight.Connection) -> SqlitePaymentRepository {
  SqlitePaymentRepository(db: db)
}

pub fn to_port(
  repository: SqlitePaymentRepository,
) -> payment_repository.PaymentRepository {
  payment_repository.PaymentRepository(
    get_payment: fn(id) { get_payment(repository, id) },
    save_payment: fn(value) { save_payment(repository, value) },
  )
}

// ----------------------------------------------------------------------------
// Repository
// ----------------------------------------------------------------------------

pub fn get_payment(
  repository: SqlitePaymentRepository,
  id: payment.PaymentId,
) -> Result(option.Option(payment.Payment), repository_error.RepositoryError) {
  let SqlitePaymentRepository(db: db) = repository

  use payment_data <- result.try(load_payment(db, id))

  case payment_data {
    [] -> Ok(option.None)

    [data] -> {
      use value <- result.try(build_payment_from_data(data))
      Ok(option.Some(value))
    }

    [_, _, ..] ->
      Error(repository_error.StorageError(
        "Multiple payments found for one payment ID",
      ))
  }
}

pub fn save_payment(
  repository: SqlitePaymentRepository,
  value: payment.Payment,
) -> Result(Nil, repository_error.RepositoryError) {
  let SqlitePaymentRepository(db: db) = repository

  let payment_id = payment.get_payment_id_value(payment.get_payment_id(value))

  let session_id =
    parking_session.get_parking_session_id_value(payment.get_payment_session_id(
      value,
    ))

  let amount = payment.get_payment_amount(value)
  let method = payment.get_payment_method(value)
  let status = payment.get_payment_status(value)
  let created_at = payment.get_payment_created_at(value)

  use method_value <- result.try(payment_method_to_string(method))
  use status_value <- result.try(payment_status_to_string(status))

  use saved_ids <- result.try(
    query(sqlight.query(
      "
    INSERT INTO payments (
      id,
      session_id,
      amount,
      method,
      status,
      created_at
    )
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      session_id = excluded.session_id,
      amount = excluded.amount,
      method = excluded.method,
      status = excluded.status,
      created_at = excluded.created_at
    RETURNING id;
    ",
      on: db,
      with: [
        sqlight.text(payment_id),
        sqlight.text(session_id),
        sqlight.int(amount),
        sqlight.text(method_value),
        sqlight.text(status_value),
        sqlight.int(created_at),
      ],
      expecting: decode.field(0, decode.string, fn(id) { decode.success(id) }),
    )),
  )

  case saved_ids {
    [saved_id] if saved_id == payment_id -> Ok(Nil)

    _ -> Error(repository_error.StorageError("Failed to persist payment"))
  }
}

// ----------------------------------------------------------------------------
// Database queries
// ----------------------------------------------------------------------------

fn load_payment(
  db: sqlight.Connection,
  id: payment.PaymentId,
) -> Result(
  List(#(String, String, Int, String, String, Int)),
  repository_error.RepositoryError,
) {
  query(sqlight.query(
    "
    SELECT
      id,
      session_id,
      amount,
      method,
      status,
      created_at
    FROM payments
    WHERE id = ?;
    ",
    on: db,
    with: [
      sqlight.text(payment.get_payment_id_value(id)),
    ],
    expecting: payment_decoder(),
  ))
}

fn payment_decoder() {
  decode.at([0], decode.string)
  |> decode.then(fn(payment_id) {
    decode.at([1], decode.string)
    |> decode.then(fn(session_id) {
      decode.at([2], decode.int)
      |> decode.then(fn(amount) {
        decode.at([3], decode.string)
        |> decode.then(fn(method) {
          decode.at([4], decode.string)
          |> decode.then(fn(status) {
            decode.at([5], decode.int)
            |> decode.map(fn(created_at) {
              #(payment_id, session_id, amount, method, status, created_at)
            })
          })
        })
      })
    })
  })
}

// ----------------------------------------------------------------------------
// Database -> Domain conversion
// ----------------------------------------------------------------------------

fn build_payment_from_data(
  data: #(String, String, Int, String, String, Int),
) -> Result(payment.Payment, repository_error.RepositoryError) {
  let #(payment_id, session_id, amount, method, status, created_at) = data

  use id <- result.try(build_payment_id(payment_id))
  use session_id <- result.try(build_session_id(session_id))
  use method <- result.try(payment_method_from_string(method))

  use value <- result.try(
    case payment.new_payment(id, session_id, amount, method, created_at) {
      Ok(value) -> Ok(value)

      Error(error) ->
        Error(repository_error.StorageError(payment.error_message(error)))
    },
  )

  apply_payment_status(value, status)
}

fn build_payment_id(
  value: String,
) -> Result(payment.PaymentId, repository_error.RepositoryError) {
  case payment.new_payment_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(repository_error.StorageError(payment.error_message(error)))
  }
}

fn build_session_id(
  value: String,
) -> Result(parking_session.ParkingSessionId, repository_error.RepositoryError) {
  case parking_session.new_parking_session_id(value) {
    Ok(id) -> Ok(id)

    Error(error) ->
      Error(repository_error.StorageError(parking_session.error_message(error)))
  }
}

fn apply_payment_status(
  value: payment.Payment,
  status: String,
) -> Result(payment.Payment, repository_error.RepositoryError) {
  case status {
    "Pending" -> Ok(value)

    "Succeeded" ->
      case payment.succeed_payment(value) {
        Ok(updated) -> Ok(updated)

        Error(error) ->
          Error(repository_error.StorageError(payment.error_message(error)))
      }

    "Failed" ->
      case payment.fail_payment(value) {
        Ok(updated) -> Ok(updated)

        Error(error) ->
          Error(repository_error.StorageError(payment.error_message(error)))
      }

    "Cancelled" ->
      case payment.cancel_payment(value) {
        Ok(updated) -> Ok(updated)

        Error(error) ->
          Error(repository_error.StorageError(payment.error_message(error)))
      }

    _ ->
      Error(repository_error.StorageError("Invalid payment status in database"))
  }
}

// ----------------------------------------------------------------------------
// Enum conversion
// ----------------------------------------------------------------------------

fn payment_method_to_string(
  method: payment.PaymentMethod,
) -> Result(String, repository_error.RepositoryError) {
  case method {
    payment.Cash -> Ok("Cash")
    payment.Qris -> Ok("Qris")
    payment.DebitCard -> Ok("DebitCard")
    payment.EWallet -> Ok("EWallet")
  }
}

fn payment_method_from_string(
  value: String,
) -> Result(payment.PaymentMethod, repository_error.RepositoryError) {
  case value {
    "Cash" -> Ok(payment.Cash)
    "Qris" -> Ok(payment.Qris)
    "DebitCard" -> Ok(payment.DebitCard)
    "EWallet" -> Ok(payment.EWallet)

    _ ->
      Error(repository_error.StorageError("Invalid payment method in database"))
  }
}

fn payment_status_to_string(
  status: payment.PaymentStatus,
) -> Result(String, repository_error.RepositoryError) {
  case status {
    payment.Pending -> Ok("Pending")
    payment.Succeeded -> Ok("Succeeded")
    payment.Failed -> Ok("Failed")
    payment.Cancelled -> Ok("Cancelled")
  }
}

// ----------------------------------------------------------------------------
// Error mapping
// ----------------------------------------------------------------------------

fn query(
  value: Result(a, sqlight.Error),
) -> Result(a, repository_error.RepositoryError) {
  case value {
    Ok(result) -> Ok(result)

    Error(sqlight.SqlightError(_, message, _)) ->
      Error(repository_error.StorageError(message))
  }
}
