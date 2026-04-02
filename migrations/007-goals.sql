-- Alba Memory: Goal hierarchy tracking
-- Migration 007 — Mission → Goal → Task tree with status tracking

CREATE TABLE IF NOT EXISTS goals (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_id     INTEGER REFERENCES goals(id) ON DELETE RESTRICT,
    type          TEXT NOT NULL CHECK (type IN ('mission', 'goal', 'task')),
    title         TEXT NOT NULL,
    description   TEXT,
    status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'done', 'blocked', 'deferred')),
    target_date   TEXT,
    created_at    TEXT NOT NULL,
    completed_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_goals_parent_id ON goals(parent_id);
CREATE INDEX IF NOT EXISTS idx_goals_status ON goals(status);

UPDATE meta SET value = '7' WHERE key = 'schema_version';
