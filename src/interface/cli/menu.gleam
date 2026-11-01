//// Defines the actions available in the parking lot CLI.

import gleam/io

pub type MenuAction {
  VehicleEntry
  VehicleExit
  ViewParkingStatus
  Quit
}

/// Displays the main menu.
pub fn display() -> Nil {
  io.println("")
  io.println("================================")
  io.println("          PARKING LOT")
  io.println("================================")
  io.println("1. Vehicle Entry")
  io.println("2. Vehicle Exit")
  io.println("3. View Parking Status")
  io.println("0. Quit")
  io.println("--------------------------------")
  io.print("Select an option: ")
}
