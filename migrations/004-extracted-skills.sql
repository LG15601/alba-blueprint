-- Alba Memory: Extracted skills table
-- Migration 004 — Track auto-extracted skills from successful session workflows

CREATE TABLE IF NOT EXISTS extracted_skills (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_name             TEXT NOT NULL,
    source_observation_ids TEXT NOT NULL,        -- comma-separated observation IDs
    content_hash           TEXT UNIQUE,          -- SHA-256 of generated SKILL.md content
    skill_path             TEXT,                 -- deployed path (e.g. ~/.claude/skills/auto-foo/)
    created_at             TEXT NOT NULL         -- ISO-8601
);

CREATE INDEX IF NOT EXISTS idx_extracted_skills_created ON extracted_skills(created_at);

UPDATE meta SET value = '4' WHERE key = 'schema_version';
