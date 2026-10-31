import domain/vehicle
import gleam/result

// MARK: Errors

pub type ParkingPricingPolicyError {
  InvalidMotorcycleHourlyRate
  InvalidCarHourlyRate
  InvalidTruckHourlyRate
}

pub fn error_message(error: ParkingPricingPolicyError) -> String {
  case error {
    InvalidMotorcycleHourlyRate ->
      "Motorcycle hourly rate must be greater than zero"

    InvalidCarHourlyRate -> "Car hourly rate must be greater than zero"

    InvalidTruckHourlyRate -> "Truck hourly rate must be greater than zero"
  }
}

// MARK: Parking Pricing Policy

pub opaque type ParkingPricingPolicy {
  ParkingPricingPolicy(
    motorcycle_hourly_rate: Int,
    car_hourly_rate: Int,
    truck_hourly_rate: Int,
  )
}

// MARK: Constructor

fn validate_motorcycle_rate(
  rate: Int,
) -> Result(Nil, ParkingPricingPolicyError) {
  case rate > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidMotorcycleHourlyRate)
  }
}

fn validate_car_rate(rate: Int) -> Result(Nil, ParkingPricingPolicyError) {
  case rate > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidCarHourlyRate)
  }
}

fn validate_truck_rate(rate: Int) -> Result(Nil, ParkingPricingPolicyError) {
  case rate > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidTruckHourlyRate)
  }
}

pub fn new_parking_pricing_policy(
  motorcycle_hourly_rate: Int,
  car_hourly_rate: Int,
  truck_hourly_rate: Int,
) -> Result(ParkingPricingPolicy, ParkingPricingPolicyError) {
  use _ <- result.try(validate_motorcycle_rate(motorcycle_hourly_rate))
  use _ <- result.try(validate_car_rate(car_hourly_rate))
  use _ <- result.try(validate_truck_rate(truck_hourly_rate))

  Ok(ParkingPricingPolicy(
    motorcycle_hourly_rate: motorcycle_hourly_rate,
    car_hourly_rate: car_hourly_rate,
    truck_hourly_rate: truck_hourly_rate,
  ))
}

// MARK: Accessors

pub fn get_motorcycle_hourly_rate(policy: ParkingPricingPolicy) -> Int {
  let ParkingPricingPolicy(motorcycle_hourly_rate: rate, ..) = policy
  rate
}

pub fn get_car_hourly_rate(policy: ParkingPricingPolicy) -> Int {
  let ParkingPricingPolicy(car_hourly_rate: rate, ..) = policy
  rate
}

pub fn get_truck_hourly_rate(policy: ParkingPricingPolicy) -> Int {
  let ParkingPricingPolicy(truck_hourly_rate: rate, ..) = policy
  rate
}

// MARK: Rate Lookup

pub fn get_hourly_rate(
  policy: ParkingPricingPolicy,
  vehicle_type: vehicle.VehicleType,
) -> Int {
  case vehicle_type {
    vehicle.Motorcycle -> get_motorcycle_hourly_rate(policy)
    vehicle.Car -> get_car_hourly_rate(policy)
    vehicle.Truck -> get_truck_hourly_rate(policy)
  }
}
