# Parking Lot — Practical DDD & Domain Modeling Made Functional with Gleam

A hands-on learning project that explores Domain-Driven Design (DDD) and Domain Modeling Made Functional using [Gleam](https://gleam.run/).

This repository uses a parking lot management system as a practical case study to demonstrate how to model business domains, express business rules, handle domain errors, and organize application architecture using functional programming principles.

The goal is not simply to build a parking lot application. It is to understand how to design software around its domain and make invalid states difficult to represent.

## Learning Goals

This project is designed for developers who want to explore the relationship between Domain-Driven Design and functional programming.

The main learning objectives are:

- **Domain Modeling:** Identify domain concepts, entities, value objects, and their responsibilities.
- **Domain-Driven Design:** Organize business logic around domain concepts rather than technical implementation details.
- **Domain Modeling Made Functional:** Use Gleam's type system, custom types, records, and pattern matching to represent business rules explicitly.
- **Domain Errors:** Model business failures as explicit domain errors instead of relying on exceptions or loosely defined error messages.
- **Functional Core:** Keep business decisions and domain behavior independent of infrastructure concerns.
- **Application Layer:** Coordinate domain operations through application use cases.
- **Ports and Adapters:** Separate application logic from infrastructure implementations.
- **Persistence:** Integrate a SQLite database without making the domain dependent on database technology.
- **Testing:** Test domain behavior, business rules, application workflows, and error scenarios.

## Why Gleam?

[Gleam](https://gleam.run/) provides a statically typed functional programming environment with an expressive type system.

Its features make it particularly interesting for domain modeling:

- Custom types for representing domain concepts and business states.
- Records for modeling structured domain data.
- `Result` and `Option` for explicit error and optional-value handling.
- Pattern matching for expressing business decisions.
- Immutable data structures and functional composition.
- Strong compile-time guarantees.

Rather than translating object-oriented designs directly into functional code, this project explores how to model the domain naturally using Gleam.

## Case Study: Parking Lot Management

The application models a parking lot management system with concepts such as:

- Parking floors
- Parking slots
- Vehicles
- Vehicle types
- Parking sessions
- Parking tickets
- Vehicle entry and exit
- Parking capacity and slot allocation

The domain is designed around business rules and constraints.

For example, vehicle entry is not simply an operation that inserts a record into a database. It involves validating the vehicle, finding a suitable parking slot, allocating that slot, creating a parking session, and generating a parking ticket.

These operations should respect domain invariants and produce meaningful errors when a business rule cannot be satisfied.

## Architecture

The project separates responsibilities into several layers:

```text
src/
├── domain/
│   └── Business concepts and domain rules
│
├── application/
│   ├── Application use cases
│   └── ports/
│       └── Interfaces required by application logic
│
├── infrastructure/
│   └── Technical implementations such as SQLite adapters
│
├── interface/
│   └── cli/
│       └── Command-line interface
│
└── main.gleam
```

### Domain Layer

Contains the core business model:

- Domain entities and value objects.
- Domain-specific types and states.
- Business rules and invariants.
- Explicit domain errors.

The domain layer should not depend on application, infrastructure, or interface implementations.

### Application Layer

Coordinates business workflows through use cases.

It defines the operations the application supports and uses ports to communicate with external dependencies.

### Infrastructure Layer

Provides technical implementations for application ports.

The current project uses SQLite for persistence.

### Interface Layer

Provides the command-line interface used to interact with the application.

The CLI is an entry point to application use cases, not a place to implement business rules.

## Technology Stack

| Technology | Purpose |
| --- | --- |
| Gleam | Main programming language |
| Erlang | Runtime target |
| SQLite | Persistence |
| SQLight | SQLite integration |
| Cake | Database access and query composition |
| Migrant | Database migrations |
| YouID | UUID generation |

## Running the Project

### Prerequisites

- Gleam toolchain
- Erlang/OTP
- Git

Clone the repository:

```sh
git clone https://github.com/<your-username>/parking_lot.git
cd parking_lot
```

Run the application:

```sh
gleam run
```

Run the test suite:

```sh
gleam test
```

Format and validate the project:

```sh
gleam format
gleam check
gleam test
```

## Project Development

The project is developed incrementally, with an emphasis on understanding the domain before implementing technical details.

The general workflow is:

1. Understand the business requirements.
2. Identify domain concepts and relationships.
3. Define domain types and invariants.
4. Model domain operations and domain errors.
5. Implement application use cases.
6. Define ports for external dependencies.
7. Implement infrastructure adapters.
8. Connect the application through an interface.
9. Write tests for business rules and application workflows.

This approach helps demonstrate how a domain model can guide the architecture rather than allowing database schemas or framework conventions to dictate the business design.

## Learning References

This project is inspired by ideas and practices from:

- [Domain-Driven Design](https://www.domainlanguage.com/ddd/)
- *Domain Modeling Made Functional* — Scott Wlaschin
- *Implementing Domain-Driven Design* — Vaughn Vernon
- *Practical Domain-Driven Design*
- [Gleam Documentation](https://gleam.run/documentation/)

These references provide conceptual foundations. The repository focuses on exploring and applying relevant ideas through a concrete Gleam implementation.

## Project Status

This is an evolving educational project.

The implementation may change as the domain model, business rules, application use cases, and infrastructure evolve.

Some design decisions are intentionally explored and refined throughout development. The repository is intended to be a practical learning resource, not a claim that there is only one correct way to implement DDD or functional domain modeling.

## Contributing

Contributions, discussions, suggestions, and constructive feedback are welcome.

If you find an issue with the domain model, business rules, architecture, or Gleam implementation, feel free to open an issue or submit a pull request.

The most valuable contributions are those that help improve the clarity of the domain model and the learning experience.

## License

See [LICENSE](LICENSE) for licensing information.
