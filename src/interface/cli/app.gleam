import application/entry_parking
import application/entry_parking_service
import domain/parking_session
import domain/parking_ticket
import gleam/time/timestamp
import interface/cli/display
import interface/cli/input
import interface/cli/menu
import interface/cli/terminal_input
import interface/cli/vehicle_input
import youid/uuid

/// Starts the interactive parking lot CLI.
pub fn run(service: entry_parking_service.EntryParkingService) -> Nil {
  display.heading("Parking Lot Management")
  run_menu(service)
}

fn run_menu(service: entry_parking_service.EntryParkingService) -> Nil {
  menu.display()

  case terminal_input.read_line() {
    Ok(raw_input) -> {
      case input.parse_menu_action(raw_input) {
        Ok(menu.VehicleEntry) -> {
          handle_vehicle_entry(service)
          run_menu(service)
        }

        Ok(menu.VehicleExit) -> {
          display.warning("Vehicle exit flow is not implemented yet.")
          run_menu(service)
        }

        Ok(menu.ViewParkingStatus) -> {
          display.warning("Parking status view is not implemented yet.")
          run_menu(service)
        }

        Ok(menu.Quit) -> display.success("Goodbye!")

        Error(input.EmptyInput) -> {
          display.warning("Input cannot be empty.")
          run_menu(service)
        }

        Error(input.InvalidInput) -> {
          display.warning("Invalid input.")
          run_menu(service)
        }

        Error(input.UnknownOption) -> {
          display.warning("Unknown menu option.")
          run_menu(service)
        }
      }
    }

    Error(Nil) -> {
      display.warning("Input stream closed. Exiting.")
    }
  }
}

fn handle_vehicle_entry(
  service: entry_parking_service.EntryParkingService,
) -> Nil {
  case vehicle_input.read_vehicle() {
    Ok(candidate_vehicle) -> {
      let session_id_value = uuid.v7_string()
      let ticket_id_value = uuid.v7_string()

      case parking_session.new_parking_session_id(session_id_value) {
        Ok(session_id) ->
          case parking_ticket.new_parking_ticket_id(ticket_id_value) {
            Ok(ticket_id) -> {
              let #(entry_time, _) =
                timestamp.system_time()
                |> timestamp.to_unix_seconds_and_nanoseconds()

              let request =
                entry_parking.EntryParkingRequest(
                  session_id: session_id,
                  ticket_id: ticket_id,
                  vehicle: candidate_vehicle,
                  entry_time: entry_time,
                )

              case entry_parking_service.enter(service, request) {
                Ok(_) ->
                  display.success("Vehicle entry completed successfully.")

                Error(error) ->
                  display.error(entry_parking_service.error_message(error))
              }
            }

            Error(_) -> display.error("Failed to generate parking ticket ID.")
          }

        Error(_) -> display.error("Failed to generate parking session ID.")
      }
    }

    Error(Nil) ->
      display.warning("Vehicle entry cancelled because input is unavailable.")
  }
}
