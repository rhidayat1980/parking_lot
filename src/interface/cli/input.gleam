import gleam/string
import interface/cli/menu

/// Errors produced while parsing a menu selection.
pub type MenuInputError {
  EmptyInput
  InvalidInput
  UnknownOption
}

/// Converts raw user input into a menu action. 
pub fn parse_menu_action(
  input: String,
) -> Result(menu.MenuAction, MenuInputError) {
  case string.trim(input) {
    "" -> Error(EmptyInput)
    "1" -> Ok(menu.VehicleEntry)
    "2" -> Ok(menu.VehicleExit)
    "3" -> Ok(menu.ViewParkingStatus)
    "0" -> Ok(menu.Quit)
    _ -> Error(UnknownOption)
  }
}
