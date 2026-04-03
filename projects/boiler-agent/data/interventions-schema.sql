-- Interventions database for Guillaume's boiler tech bot
-- Location: ~/.claude/channels/telegram-guillaume/interventions.db

CREATE TABLE IF NOT EXISTS interventions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_start TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    date_end TEXT,
    client_name TEXT NOT NULL,
    client_location TEXT,
    boiler_brand TEXT DEFAULT 'HERZ',
    boiler_model TEXT DEFAULT 'Firematic 130',
    boiler_serial TEXT,
    fault_codes TEXT,           -- comma-separated: "080,093,025"
    fault_description TEXT,     -- plain text symptom description
    diagnosis TEXT,             -- root cause identified
    solution TEXT,              -- what was done
    parts_replaced TEXT,        -- JSON: [{"ref":"SP.00.00300","name":"Moteur vis","qty":1}]
    tools_used TEXT,            -- comma-separated
    tests_performed TEXT,       -- measurements, values
    result TEXT CHECK(result IN ('resolu', 'en_attente_piece', 'a_surveiller', 'en_cours')),
    observations TEXT,          -- notes, recommendations
    next_intervention TEXT,     -- suggested next date or condition
    photos TEXT,                -- JSON array of file paths
    status TEXT DEFAULT 'en_cours' CHECK(status IN ('en_cours', 'termine')),
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_interventions_client ON interventions(client_name);
CREATE INDEX IF NOT EXISTS idx_interventions_date ON interventions(date_start DESC);
CREATE INDEX IF NOT EXISTS idx_interventions_status ON interventions(status);
CREATE INDEX IF NOT EXISTS idx_interventions_fault ON interventions(fault_codes);

-- Trigger to auto-update updated_at
CREATE TRIGGER IF NOT EXISTS trg_interventions_updated
    AFTER UPDATE ON interventions
    FOR EACH ROW
BEGIN
    UPDATE interventions SET updated_at = datetime('now', 'localtime') WHERE id = OLD.id;
END;
