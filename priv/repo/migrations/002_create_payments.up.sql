CREATE TABLE payments (
    id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    method TEXT NOT NULL CHECK (
        method IN ('Cash', 'Qris', 'DebitCard', 'EWallet')
    ),
    status TEXT NOT NULL CHECK (
        status IN ('Pending', 'Succeeded', 'Failed', 'Cancelled')
    ),
    created_at INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES parking_sessions(id) ON DELETE RESTRICT
);
CREATE INDEX idx_payments_session_id ON payments(session_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE UNIQUE INDEX idx_payments_one_success_per_session ON payments(session_id)
WHERE status = 'Succeeded';