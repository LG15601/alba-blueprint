-- Alba Memory: Centralized logs table
-- Migration 005 — Structured logging for all Alba components

CREATE TABLE IF NOT EXISTS logs (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,          -- ISO-8601
    level     TEXT NOT NULL,          -- DEBUG|INFO|WARN|ERROR|CRITICAL
    source    TEXT NOT NULL,          -- component identifier (e.g. watchdog, hook, memory-guard)
    component TEXT,                   -- optional sub-component
    message   TEXT NOT NULL,
    metadata  TEXT                    -- optional JSON blob
);

CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_level ON logs(level);
CREATE INDEX IF NOT EXISTS idx_logs_source ON logs(source);

UPDATE meta SET value = '5' WHERE key = 'schema_version';
