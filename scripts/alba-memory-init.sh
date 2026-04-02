#!/usr/bin/env bash
# alba-memory-init.sh — Initialize and migrate the Alba memory database
# Usage: bash scripts/alba-memory-init.sh [db_path]
#
# Creates ~/.alba/alba-memory.db (or custom path) with WAL mode and
# applies numbered migrations from migrations/ directory.

set -euo pipefail

DB_PATH="${1:-$HOME/.alba/alba-memory.db}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONS_DIR="${SCRIPT_DIR}/../migrations"

# Ensure parent directory exists
mkdir -p "$(dirname "$DB_PATH")"

# ── Pragma optimizations ─────────────────────────────────────
# Applied on every init to ensure WAL mode and performance settings persist
sqlite3 "$DB_PATH" <<'PRAGMA' > /dev/null
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA mmap_size = 268435456;
PRAGMA cache_size = 10000;
PRAGMA foreign_keys = ON;
PRAGMA

# ── Bootstrap meta table if needed ───────────────────────────
sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);"
sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO meta (key, value) VALUES ('schema_version', '0');"

# ── Read current version ─────────────────────────────────────
current_version=$(sqlite3 "$DB_PATH" "SELECT value FROM meta WHERE key = 'schema_version';")
current_version="${current_version:-0}"

# ── Apply pending migrations ─────────────────────────────────
applied=0
for migration_file in "$MIGRATIONS_DIR"/[0-9][0-9][0-9]-*.sql; do
    [ -f "$migration_file" ] || continue

    # Extract version number from filename (e.g., 001-initial-schema.sql → 1)
    basename_file="$(basename "$migration_file")"
    file_version=$(echo "$basename_file" | sed 's/^0*//' | cut -d'-' -f1)
    file_version="${file_version:-0}"

    if [ "$file_version" -gt "$current_version" ]; then
        echo "Applying migration: $basename_file"
        sqlite3 "$DB_PATH" < "$migration_file"
        applied=$((applied + 1))
    fi
done

if [ "$applied" -eq 0 ]; then
    echo "Database up to date (version $current_version)"
else
    new_version=$(sqlite3 "$DB_PATH" "SELECT value FROM meta WHERE key = 'schema_version';")
    echo "Applied $applied migration(s) — now at version $new_version"
fi

# ── Verify core tables exist ─────────────────────────────────
tables=$(sqlite3 "$DB_PATH" ".tables")
for required_table in sessions observations session_summaries observations_fts meta logs; do
    if ! echo "$tables" | grep -qw "$required_table"; then
        echo "ERROR: Required table '$required_table' missing after migration" >&2
        exit 1
    fi
done

echo "Alba memory database ready: $DB_PATH"
