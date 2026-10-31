import domain/parking_pricing_policy
import domain/vehicle
import gleeunit/should

// MARK: Test Helpers

fn create_pricing_policy() -> parking_pricing_policy.ParkingPricingPolicy {
  let assert Ok(policy) =
    parking_pricing_policy.new_parking_pricing_policy(2000, 5000, 10_000)

  policy
}

// MARK: Construction

pub fn pricing_policy_accepts_valid_rates_test() {
  let result =
    parking_pricing_policy.new_parking_pricing_policy(2000, 5000, 10_000)

  should.be_ok(result)
}

pub fn pricing_policy_rejects_zero_motorcycle_rate_test() {
  should.equal(
    parking_pricing_policy.new_parking_pricing_policy(0, 5000, 10_000),
    Error(parking_pricing_policy.InvalidMotorcycleHourlyRate),
  )
}

pub fn pricing_policy_rejects_negative_motorcycle_rate_test() {
  should.equal(
    parking_pricing_policy.new_parking_pricing_policy(-2000, 5000, 10_000),
    Error(parking_pricing_policy.InvalidMotorcycleHourlyRate),
  )
}

pub fn pricing_policy_rejects_zero_car_rate_test() {
  should.equal(
    parking_pricing_policy.new_parking_pricing_policy(2000, 0, 10_000),
    Error(parking_pricing_policy.InvalidCarHourlyRate),
  )
}

pub fn pricing_policy_rejects_negative_car_rate_test() {
  should.equal(
    parking_pricing_policy.new_parking_pricing_policy(2000, -5000, 10_000),
    Error(parking_pricing_policy.InvalidCarHourlyRate),
  )
}

pub fn pricing_policy_rejects_zero_truck_rate_test() {
  should.equal(
    parking_pricing_policy.new_parking_pricing_policy(2000, 5000, 0),
    Error(parking_pricing_policy.InvalidTruckHourlyRate),
  )
}

pub fn pricing_policy_rejects_negative_truck_rate_test() {
  should.equal(
    parking_pricing_policy.new_parking_pricing_policy(2000, 5000, -10_000),
    Error(parking_pricing_policy.InvalidTruckHourlyRate),
  )
}

// MARK: Accessors

pub fn motorcycle_hourly_rate_accessor_test() {
  let policy = create_pricing_policy()

  should.equal(parking_pricing_policy.get_motorcycle_hourly_rate(policy), 2000)
}

pub fn car_hourly_rate_accessor_test() {
  let policy = create_pricing_policy()

  should.equal(parking_pricing_policy.get_car_hourly_rate(policy), 5000)
}

pub fn truck_hourly_rate_accessor_test() {
  let policy = create_pricing_policy()

  should.equal(parking_pricing_policy.get_truck_hourly_rate(policy), 10_000)
}

// MARK: Vehicle Rate Lookup

pub fn get_hourly_rate_returns_motorcycle_rate_test() {
  let policy = create_pricing_policy()

  should.equal(
    parking_pricing_policy.get_hourly_rate(policy, vehicle.Motorcycle),
    2000,
  )
}

pub fn get_hourly_rate_returns_car_rate_test() {
  let policy = create_pricing_policy()

  should.equal(
    parking_pricing_policy.get_hourly_rate(policy, vehicle.Car),
    5000,
  )
}

pub fn get_hourly_rate_returns_truck_rate_test() {
  let policy = create_pricing_policy()

  should.equal(
    parking_pricing_policy.get_hourly_rate(policy, vehicle.Truck),
    10_000,
  )
}
