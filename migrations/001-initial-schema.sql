-- Alba Memory: Initial schema
-- Migration 001 — SQLite with FTS5 full-text search

-- ============================================================
-- Meta table for migration version tracking
-- ============================================================
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT OR IGNORE INTO meta (key, value) VALUES ('schema_version', '0');

-- ============================================================
-- Sessions — one row per Claude Code session
-- ============================================================
CREATE TABLE IF NOT EXISTS sessions (
    id              TEXT PRIMARY KEY,   -- UUID or session identifier
    project         TEXT NOT NULL,      -- project path or name
    started_at      TEXT NOT NULL,      -- ISO-8601
    ended_at        TEXT,               -- ISO-8601, NULL while active
    message_count   INTEGER DEFAULT 0,
    tool_call_count INTEGER DEFAULT 0,
    title           TEXT,               -- human-readable session title
    summary         TEXT                -- short summary text
);

CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project);
CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at);

-- ============================================================
-- Observations — individual captured events within a session
-- ============================================================
CREATE TABLE IF NOT EXISTS observations (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id     TEXT NOT NULL REFERENCES sessions(id),
    type           TEXT NOT NULL CHECK(type IN (
                       'decision', 'bugfix', 'feature',
                       'refactor', 'discovery', 'change'
                   )),
    title          TEXT NOT NULL,
    subtitle       TEXT,
    narrative      TEXT,
    facts          TEXT,           -- JSON array
    concepts       TEXT,           -- JSON array
    files_read     TEXT,           -- JSON array
    files_modified TEXT,           -- JSON array
    tokens_cost    INTEGER DEFAULT 0,
    created_at     TEXT NOT NULL   -- ISO-8601
);

CREATE INDEX IF NOT EXISTS idx_observations_session ON observations(session_id);
CREATE INDEX IF NOT EXISTS idx_observations_type    ON observations(type);
CREATE INDEX IF NOT EXISTS idx_observations_created ON observations(created_at);

-- ============================================================
-- Session summaries — structured end-of-session record
-- ============================================================
CREATE TABLE IF NOT EXISTS session_summaries (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   TEXT NOT NULL UNIQUE REFERENCES sessions(id),
    request      TEXT,           -- what was asked
    investigated TEXT,           -- what was explored
    learned      TEXT,           -- insights gained
    completed    TEXT,           -- what was delivered
    next_steps   TEXT            -- follow-up items
);

-- ============================================================
-- FTS5 virtual table for full-text search on observations
-- ============================================================
CREATE VIRTUAL TABLE IF NOT EXISTS observations_fts USING fts5(
    title,
    subtitle,
    narrative,
    facts,
    concepts,
    content='observations',
    content_rowid='id'
);

-- ============================================================
-- Triggers to keep FTS5 index in sync with observations table
-- ============================================================

-- After INSERT: add new row to FTS index
CREATE TRIGGER IF NOT EXISTS observations_ai AFTER INSERT ON observations BEGIN
    INSERT INTO observations_fts(rowid, title, subtitle, narrative, facts, concepts)
    VALUES (new.id, new.title, new.subtitle, new.narrative, new.facts, new.concepts);
END;

-- Before DELETE: remove old row from FTS index
CREATE TRIGGER IF NOT EXISTS observations_bd BEFORE DELETE ON observations BEGIN
    INSERT INTO observations_fts(observations_fts, rowid, title, subtitle, narrative, facts, concepts)
    VALUES ('delete', old.id, old.title, old.subtitle, old.narrative, old.facts, old.concepts);
END;

-- Before UPDATE: remove old, then after update add new
CREATE TRIGGER IF NOT EXISTS observations_bu BEFORE UPDATE ON observations BEGIN
    INSERT INTO observations_fts(observations_fts, rowid, title, subtitle, narrative, facts, concepts)
    VALUES ('delete', old.id, old.title, old.subtitle, old.narrative, old.facts, old.concepts);
END;

CREATE TRIGGER IF NOT EXISTS observations_au AFTER UPDATE ON observations BEGIN
    INSERT INTO observations_fts(rowid, title, subtitle, narrative, facts, concepts)
    VALUES (new.id, new.title, new.subtitle, new.narrative, new.facts, new.concepts);
END;

-- ============================================================
-- Mark migration as applied
-- ============================================================
UPDATE meta SET value = '1' WHERE key = 'schema_version';
