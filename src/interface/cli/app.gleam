import interface/cli/display
import interface/cli/input
import interface/cli/menu
import interface/cli/terminal_input

/// Starts the interactive parking lot CLI.
pub fn run() -> Nil {
  display.heading("Parking Lot Management")
  run_menu()
}

fn run_menu() -> Nil {
  menu.display()

  case terminal_input.read_line() {
    Ok(raw_input) -> {
      case input.parse_menu_action(raw_input) {
        Ok(menu.VehicleEntry) -> {
          display.warning("Vehicle entry flow is not implemented yet.")
          run_menu()
        }

        Ok(menu.VehicleExit) -> {
          display.warning("Vehicle exit flow is not implemented yet.")
          run_menu()
        }

        Ok(menu.ViewParkingStatus) -> {
          display.warning("Parking status view is not implemented yet.")
          run_menu()
        }

        Ok(menu.Quit) -> display.success("Goodbye!")

        Error(input.EmptyInput) -> {
          display.warning("Input cannot be empty.")
          run_menu()
        }

        Error(input.InvalidInput) -> {
          display.warning("Invalid input.")
          run_menu()
        }

        Error(input.UnknownOption) -> {
          display.warning("Unknown menu option.")
          run_menu()
        }
      }
    }

    Error(Nil) -> {
      display.warning("Input stream closed. Exiting.")
    }
  }
}
