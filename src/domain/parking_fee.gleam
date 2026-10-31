import gleam/int

// MARK: Errors

pub type ParkingFeeError {
  InvalidDuration
  InvalidHourlyRate
}

pub fn error_message(error: ParkingFeeError) -> String {
  case error {
    InvalidDuration -> "Parking duration cannot be negative"
    InvalidHourlyRate -> "Hourly rate must be greater than zero"
  }
}

// MARK: Constants

const seconds_per_hour = 3600

const rounding_offset = 1800

// MARK: Fee Calculation

/// Calculates a parking fee proportionally to the actual duration.
///
/// The result is rounded to the nearest whole rupiah.
/// A half-rupiah is rounded up.
///
/// Example:
/// - 10 minutes at Rp5,000/hour = Rp833
/// - 30 minutes at Rp5,000/hour = Rp2,500
pub fn calculate_parking_fee(
  duration_seconds: Int,
  hourly_rate: Int,
) -> Result(Int, ParkingFeeError) {
  case duration_seconds < 0 {
    True -> Error(InvalidDuration)
    False -> {
      case hourly_rate <= 0 {
        True -> Error(InvalidHourlyRate)
        False -> {
          let numerator = duration_seconds * hourly_rate + rounding_offset

          // The denominator is a non-zero constant, so division
          // cannot fail.
          let assert Ok(fee) = int.divide(numerator, seconds_per_hour)

          Ok(fee)
        }
      }
    }
  }
}
