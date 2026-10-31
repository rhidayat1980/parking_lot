import application/ports/repository_error
import domain/payment
import gleam/option.{type Option}

// MARK: Payment Repository

pub type PaymentRepository {
  PaymentRepository(
    get_payment: fn(payment.PaymentId) ->
      Result(Option(payment.Payment), repository_error.RepositoryError),
    save_payment: fn(payment.Payment) ->
      Result(Nil, repository_error.RepositoryError),
  )
}
