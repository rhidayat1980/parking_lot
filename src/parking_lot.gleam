import application/ports/repository_error
import application/seed_parking_layout
import domain/floor
import domain/parking_slot
import gleam/io
import infrastructure/sqlite_database
import infrastructure/sqlite_floor_repository
import interface/cli/app

pub fn main() -> Nil {
  case sqlite_database.connect() {
    Ok(db) -> {
      let floor_repository =
        sqlite_floor_repository.new(db)
        |> sqlite_floor_repository.to_port

      case seed_parking_layout.seed(floor_repository) {
        Ok(Nil) -> {
          io.println("Parking layout seeded successfully")
          app.run()
        }

        Error(error) ->
          io.println(
            "Parking layout seeding failed: " <> seed_error_message(error),
          )
      }
    }

    Error(repository_error) ->
      io.println(
        "Database initialization failed: "
        <> repository_error.error_message(repository_error),
      )
  }
}

fn seed_error_message(
  error: seed_parking_layout.SeedParkingLayoutError,
) -> String {
  case error {
    seed_parking_layout.InvalidFloorId(domain_error) ->
      "Invalid floor ID: " <> floor.error_message(domain_error)

    seed_parking_layout.InvalidSlotId(domain_error) ->
      "Invalid slot ID: " <> parking_slot.error_message(domain_error)

    seed_parking_layout.FloorConfigurationFailed(domain_error) ->
      "Floor configuration failed: " <> floor.error_message(domain_error)

    seed_parking_layout.RepositoryFailed(repository_error) ->
      "Repository failed: " <> repository_error.error_message(repository_error)
  }
}
