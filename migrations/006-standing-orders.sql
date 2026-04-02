-- Alba Memory: Standing order execution tracking
-- Migration 006 — Tracks when scheduled standing orders execute

CREATE TABLE IF NOT EXISTS standing_order_executions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id      TEXT NOT NULL,          -- slug derived from description (e.g. morning-briefing)
    scheduled_time TEXT NOT NULL,         -- HH:MM from standing-orders.md
    executed_at   TEXT NOT NULL,          -- ISO-8601 timestamp
    result        TEXT,                   -- stdout/stderr summary (truncated)
    duration_ms   INTEGER,               -- execution wall-clock time
    exit_code     INTEGER                 -- 0 = success
);

CREATE INDEX IF NOT EXISTS idx_so_order_id ON standing_order_executions(order_id);
CREATE INDEX IF NOT EXISTS idx_so_executed_at ON standing_order_executions(executed_at);

UPDATE meta SET value = '6' WHERE key = 'schema_version';
