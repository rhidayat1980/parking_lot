DROP INDEX IF EXISTS idx_parking_sessions_vehicle_id;
DROP INDEX IF EXISTS idx_parking_sessions_one_active_per_slot;
DROP INDEX IF EXISTS idx_parking_sessions_one_active_per_vehicle;
DROP TABLE IF EXISTS parking_tickets;
DROP TABLE IF EXISTS parking_sessions;
DROP TABLE IF EXISTS vehicles;
DROP TABLE IF EXISTS parking_slots;
DROP TABLE IF EXISTS parking_floors;