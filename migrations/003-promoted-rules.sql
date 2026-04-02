-- Alba Memory: Promoted rules table
-- Migration 003 — Track auto-promoted patterns that became Claude Code rules

CREATE TABLE IF NOT EXISTS promoted_rules (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_name           TEXT NOT NULL,
    source_learning_ids TEXT NOT NULL,        -- comma-separated learning IDs
    content_hash        TEXT UNIQUE,          -- SHA-256 of generated rule content
    created_at          TEXT NOT NULL         -- ISO-8601
);

CREATE INDEX IF NOT EXISTS idx_promoted_rules_created ON promoted_rules(created_at);

UPDATE meta SET value = '3' WHERE key = 'schema_version';
