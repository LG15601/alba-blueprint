#!/usr/bin/env bash
# alba-goals.sh — Manage goal hierarchy (mission → goal → task)
#
# Usage:
#   alba-goals.sh add --type <mission|goal|task> --title <title> [--parent <id>] [--target <date>] [--description <desc>]
#   alba-goals.sh tree                     — show indented hierarchy with status
#   alba-goals.sh done <id>                — mark goal complete
#   alba-goals.sh block <id>               — mark goal blocked
#   alba-goals.sh list [--status <s>] [--type <t>]  — flat filtered listing
#
# Environment:
#   ALBA_MEMORY_DB  — override DB path (default: ~/.alba/alba-memory.db)

# Cron-compatible PATH
PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

set -euo pipefail

ALBA_MEMORY_DB="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source logging (all log output to stderr/file, never stdout)
# shellcheck source=alba-log.sh
source "${SCRIPT_DIR}/alba-log.sh"

if [ ! -f "$ALBA_MEMORY_DB" ]; then
    echo "ERROR: Memory database not found: $ALBA_MEMORY_DB" >&2
    echo "Run: bash scripts/alba-memory-init.sh" >&2
    exit 1
fi

# ── Helpers ──────────────────────────────────────────────────

sql_escape() {
    echo "$1" | sed "s/'/''/g"
}

validate_id_exists() {
    local id="$1"
    local exists
    exists=$(/usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
        "SELECT COUNT(*) FROM goals WHERE id = $id;" 2>/dev/null)
    if [ "$exists" -eq 0 ]; then
        echo "ERROR: Goal ID $id does not exist" >&2
        exit 1
    fi
}

get_type_for_id() {
    /usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
        "SELECT type FROM goals WHERE id = $1;" 2>/dev/null
}

# Enforce type hierarchy: mission has no parent, goal→mission, task→goal
validate_hierarchy() {
    local type="$1"
    local parent_id="${2:-}"

    case "$type" in
        mission)
            if [ -n "$parent_id" ]; then
                echo "ERROR: Missions cannot have a parent" >&2
                exit 1
            fi
            ;;
        goal)
            if [ -z "$parent_id" ]; then
                echo "ERROR: Goals must have a parent (--parent <mission_id>)" >&2
                exit 1
            fi
            local parent_type
            parent_type=$(get_type_for_id "$parent_id")
            if [ "$parent_type" != "mission" ]; then
                echo "ERROR: Goal's parent must be a mission (got: ${parent_type:-not found})" >&2
                exit 1
            fi
            ;;
        task)
            if [ -z "$parent_id" ]; then
                echo "ERROR: Tasks must have a parent (--parent <goal_id>)" >&2
                exit 1
            fi
            local parent_type
            parent_type=$(get_type_for_id "$parent_id")
            if [ "$parent_type" != "goal" ]; then
                echo "ERROR: Task's parent must be a goal (got: ${parent_type:-not found})" >&2
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Invalid type '$type' — must be mission, goal, or task" >&2
            exit 1
            ;;
    esac
}

status_emoji() {
    case "$1" in
        done)     echo "✅" ;;
        blocked)  echo "🔴" ;;
        deferred) echo "⏸ " ;;
        *)        echo "  " ;;
    esac
}

# ── Subcommands ──────────────────────────────────────────────

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
    add)
        # Parse named arguments
        type="" title="" parent_id="" target_date="" description=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --type)    type="$2"; shift 2 ;;
                --title)   title="$2"; shift 2 ;;
                --parent)  parent_id="$2"; shift 2 ;;
                --target)  target_date="$2"; shift 2 ;;
                --description) description="$2"; shift 2 ;;
                *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
            esac
        done

        if [ -z "$type" ] || [ -z "$title" ]; then
            echo "Usage: alba-goals.sh add --type <mission|goal|task> --title <title> [--parent <id>] [--target <date>] [--description <desc>]" >&2
            exit 1
        fi

        # Validate parent exists if specified
        if [ -n "$parent_id" ]; then
            validate_id_exists "$parent_id"
        fi

        # Enforce type hierarchy
        validate_hierarchy "$type" "$parent_id"

        timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        parent_val="${parent_id:-NULL}"
        [ "$parent_val" != "NULL" ] || parent_val="NULL"

        target_val="NULL"
        [ -z "$target_date" ] || target_val="'$(sql_escape "$target_date")'"

        desc_val="NULL"
        [ -z "$description" ] || desc_val="'$(sql_escape "$description")'"

        new_id=$(/usr/bin/sqlite3 "$ALBA_MEMORY_DB" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO goals (parent_id, type, title, description, status, target_date, created_at)
VALUES ($parent_val, '$(sql_escape "$type")', '$(sql_escape "$title")', $desc_val, 'active', $target_val, '$timestamp');
SELECT last_insert_rowid();
SQL
        )
        echo "Created $type #$new_id: $title"
        alba_log INFO goals "Created $type #$new_id: $title"
        ;;

    tree)
        # Recursive CTE with depth guard, indented display
        /usr/bin/sqlite3 "$ALBA_MEMORY_DB" <<'SQL' | while IFS='|' read -r depth status type title gid; do
WITH RECURSIVE goal_tree AS (
    SELECT id, parent_id, type, title, status, 0 AS depth
    FROM goals WHERE parent_id IS NULL
    UNION ALL
    SELECT g.id, g.parent_id, g.type, g.title, g.status, gt.depth + 1
    FROM goals g
    JOIN goal_tree gt ON g.parent_id = gt.id
    WHERE gt.depth < 10
)
SELECT depth, status, type, title, id FROM goal_tree ORDER BY depth, id;
SQL
            [ -z "$depth" ] && continue
            emoji=$(status_emoji "$status")
            if [ "$depth" -gt 0 ]; then
                printf "%*s%s [%s] #%s %s\n" "$((depth * 2))" "" "$emoji" "$type" "$gid" "$title"
            else
                printf "%s [%s] #%s %s\n" "$emoji" "$type" "$gid" "$title"
            fi
        done
        ;;

    done)
        id="${1:-}"
        if [ -z "$id" ]; then
            echo "Usage: alba-goals.sh done <id>" >&2
            exit 1
        fi
        validate_id_exists "$id"
        timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        /usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
            "UPDATE goals SET status = 'done', completed_at = '$timestamp' WHERE id = $id;"
        echo "Marked #$id as done"
        alba_log INFO goals "Marked #$id as done"
        ;;

    block)
        id="${1:-}"
        if [ -z "$id" ]; then
            echo "Usage: alba-goals.sh block <id>" >&2
            exit 1
        fi
        validate_id_exists "$id"
        /usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
            "UPDATE goals SET status = 'blocked' WHERE id = $id;"
        echo "Marked #$id as blocked"
        alba_log INFO goals "Marked #$id as blocked"
        ;;

    list)
        # Parse optional filters
        filter_status="" filter_type=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --status) filter_status="$2"; shift 2 ;;
                --type)   filter_type="$2"; shift 2 ;;
                *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
            esac
        done

        where_clauses=()
        [ -n "$filter_status" ] && where_clauses+=("status = '$(sql_escape "$filter_status")'")
        [ -n "$filter_type" ]   && where_clauses+=("type = '$(sql_escape "$filter_type")'")

        where=""
        if [ ${#where_clauses[@]} -gt 0 ]; then
            where="WHERE $(IFS=' AND '; echo "${where_clauses[*]}")"
        fi

        printf "%-4s %-8s %-8s %-8s %s\n" "ID" "TYPE" "STATUS" "PARENT" "TITLE"
        printf "%-4s %-8s %-8s %-8s %s\n" "----" "--------" "--------" "--------" "-----"
        /usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
            "SELECT id, type, status, COALESCE(parent_id, '-'), title FROM goals $where ORDER BY id;" \
            2>/dev/null | while IFS='|' read -r gid gtype gstatus gparent gtitle; do
            printf "%-4s %-8s %-8s %-8s %s\n" "$gid" "$gtype" "$gstatus" "$gparent" "$gtitle"
        done
        ;;

    *)
        echo "Usage: alba-goals.sh {add|tree|done|block|list} [args...]" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  add   --type <mission|goal|task> --title <title> [--parent <id>]" >&2
        echo "  tree  Show goal hierarchy" >&2
        echo "  done  <id>   Mark complete" >&2
        echo "  block <id>   Mark blocked" >&2
        echo "  list  [--status <s>] [--type <t>]  Filtered listing" >&2
        exit 1
        ;;
esac
