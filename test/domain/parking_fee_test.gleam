import domain/parking_fee
import gleeunit/should

// MARK: Validation

pub fn parking_fee_rejects_negative_duration_test() {
  should.equal(
    parking_fee.calculate_parking_fee(-1, 5000),
    Error(parking_fee.InvalidDuration),
  )
}

pub fn parking_fee_rejects_zero_hourly_rate_test() {
  should.equal(
    parking_fee.calculate_parking_fee(3600, 0),
    Error(parking_fee.InvalidHourlyRate),
  )
}

pub fn parking_fee_rejects_negative_hourly_rate_test() {
  should.equal(
    parking_fee.calculate_parking_fee(3600, -5000),
    Error(parking_fee.InvalidHourlyRate),
  )
}

// MARK: Proportional Calculation

pub fn parking_fee_for_zero_duration_is_zero_test() {
  should.equal(parking_fee.calculate_parking_fee(0, 5000), Ok(0))
}

pub fn parking_fee_for_ten_minutes_is_proportional_test() {
  should.equal(parking_fee.calculate_parking_fee(600, 5000), Ok(833))
}

pub fn parking_fee_for_fifteen_minutes_is_proportional_test() {
  should.equal(parking_fee.calculate_parking_fee(900, 5000), Ok(1250))
}

pub fn parking_fee_for_thirty_minutes_is_proportional_test() {
  should.equal(parking_fee.calculate_parking_fee(1800, 5000), Ok(2500))
}

pub fn parking_fee_for_one_hour_test() {
  should.equal(parking_fee.calculate_parking_fee(3600, 5000), Ok(5000))
}

pub fn parking_fee_for_seventy_minutes_is_proportional_test() {
  should.equal(parking_fee.calculate_parking_fee(4200, 5000), Ok(5833))
}

// MARK: Rounding

pub fn parking_fee_rounds_fraction_below_half_down_test() {
  // 1 second at Rp1,000/hour = Rp0.277...
  should.equal(parking_fee.calculate_parking_fee(1, 1000), Ok(0))
}

pub fn parking_fee_rounds_half_rupiah_up_test() {
  // 18 seconds at Rp100/hour = exactly Rp0.5.
  should.equal(parking_fee.calculate_parking_fee(18, 100), Ok(1))
}

pub fn parking_fee_rounds_fraction_above_half_up_test() {
  // 19 seconds at Rp100/hour = Rp0.527...
  should.equal(parking_fee.calculate_parking_fee(19, 100), Ok(1))
}

// MARK: Different Hourly Rates

pub fn parking_fee_uses_the_supplied_hourly_rate_test() {
  should.equal(parking_fee.calculate_parking_fee(1800, 10_000), Ok(5000))
}

pub fn parking_fee_calculates_large_duration_test() {
  // 24 hours at Rp5,000/hour.
  should.equal(parking_fee.calculate_parking_fee(86_400, 5000), Ok(120_000))
}
