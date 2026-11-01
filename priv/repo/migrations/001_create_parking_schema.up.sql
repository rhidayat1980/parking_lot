PRAGMA foreign_keys = ON;
CREATE TABLE parking_floors (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0)
);
CREATE TABLE parking_slots (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
    floor_id TEXT NOT NULL,
    supported_vehicle_type TEXT NOT NULL CHECK (
        supported_vehicle_type IN ('Motorcycle', 'Car', 'Truck')
    ),
    FOREIGN KEY (floor_id) REFERENCES parking_floors(id) ON DELETE RESTRICT,
    UNIQUE (floor_id, id)
);
CREATE TABLE vehicles (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
    plate_number TEXT NOT NULL CHECK (length(trim(plate_number)) > 0),
    vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('Motorcycle', 'Car', 'Truck'))
);
CREATE TABLE parking_sessions (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
    vehicle_id TEXT NOT NULL,
    slot_id TEXT NOT NULL,
    entry_time INTEGER NOT NULL CHECK (entry_time >= 0),
    exit_time INTEGER CHECK (
        exit_time IS NULL
        OR exit_time >= entry_time
    ),
    state TEXT NOT NULL CHECK (state IN ('Active', 'Closed')),
    CHECK (
        (
            state = 'Active'
            AND exit_time IS NULL
        )
        OR (
            state = 'Closed'
            AND exit_time IS NOT NULL
        )
    ),
    FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE RESTRICT,
    FOREIGN KEY (slot_id) REFERENCES parking_slots(id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX idx_parking_sessions_one_active_per_vehicle ON parking_sessions(vehicle_id)
WHERE state = 'Active';
CREATE UNIQUE INDEX idx_parking_sessions_one_active_per_slot ON parking_sessions(slot_id)
WHERE state = 'Active';
CREATE INDEX idx_parking_sessions_vehicle_id ON parking_sessions(vehicle_id);
CREATE TABLE parking_tickets (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
    session_id TEXT NOT NULL UNIQUE,
    issued_at INTEGER NOT NULL CHECK (issued_at >= 0),
    FOREIGN KEY (session_id) REFERENCES parking_sessions(id) ON DELETE RESTRICT
);