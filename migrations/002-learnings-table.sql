-- Alba Memory: Learnings table
-- Migration 002 — Operational learnings with FTS5 full-text search

-- ============================================================
-- Learnings — distilled knowledge from session observations
-- ============================================================
CREATE TABLE IF NOT EXISTS learnings (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   TEXT NOT NULL REFERENCES sessions(id),
    source       TEXT NOT NULL CHECK(source IN ('observation', 'jsonl', 'manual')),
    content      TEXT NOT NULL,
    content_hash TEXT UNIQUE,        -- SHA-256 for deduplication
    category     TEXT,               -- e.g. 'pattern', 'gotcha', 'tool-usage'
    created_at   TEXT NOT NULL       -- ISO-8601
);

CREATE INDEX IF NOT EXISTS idx_learnings_session  ON learnings(session_id);
CREATE INDEX IF NOT EXISTS idx_learnings_category ON learnings(category);
CREATE INDEX IF NOT EXISTS idx_learnings_created  ON learnings(created_at);

-- ============================================================
-- FTS5 virtual table for full-text search on learnings
-- ============================================================
CREATE VIRTUAL TABLE IF NOT EXISTS learnings_fts USING fts5(
    content,
    category,
    content='learnings',
    content_rowid='id'
);

-- ============================================================
-- Triggers to keep FTS5 index in sync with learnings table
-- (Before-delete + after-insert pattern per KNOWLEDGE.md M005)
-- ============================================================

-- After INSERT: add new row to FTS index
CREATE TRIGGER IF NOT EXISTS learnings_ai AFTER INSERT ON learnings BEGIN
    INSERT INTO learnings_fts(rowid, content, category)
    VALUES (new.id, new.content, new.category);
END;

-- Before DELETE: remove old row from FTS index
CREATE TRIGGER IF NOT EXISTS learnings_bd BEFORE DELETE ON learnings BEGIN
    INSERT INTO learnings_fts(learnings_fts, rowid, content, category)
    VALUES ('delete', old.id, old.content, old.category);
END;

-- Before UPDATE: remove old FTS entry
CREATE TRIGGER IF NOT EXISTS learnings_bu BEFORE UPDATE ON learnings BEGIN
    INSERT INTO learnings_fts(learnings_fts, rowid, content, category)
    VALUES ('delete', old.id, old.content, old.category);
END;

-- After UPDATE: add new FTS entry
CREATE TRIGGER IF NOT EXISTS learnings_au AFTER UPDATE ON learnings BEGIN
    INSERT INTO learnings_fts(rowid, content, category)
    VALUES (new.id, new.content, new.category);
END;

-- ============================================================
-- Mark migration as applied
-- ============================================================
UPDATE meta SET value = '2' WHERE key = 'schema_version';
