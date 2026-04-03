#!/usr/bin/env bash
# alba-fallback.sh — Local Gemma 4 fallback for when Claude is unavailable
#
# Usage:
#   alba-fallback.sh status          # Check Ollama + model availability
#   alba-fallback.sh "your query"    # Query Gemma 4 via Ollama
#   echo "query" | alba-fallback.sh  # Query via stdin
#
# Environment:
#   OLLAMA_URL            — Ollama API base (default: http://localhost:11434)
#   ALBA_FALLBACK_MODEL   — model name (default: gemma4)
#
# Exit codes:
#   0 = success
#   1 = Ollama not running
#   2 = model not available
#   3 = query failed

set -u

# ---- Source shared logging ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=alba-log.sh
source "$SCRIPT_DIR/alba-log.sh" 2>/dev/null || {
    # Minimal fallback if alba-log.sh unavailable
    alba_log() { echo "[$1] $2: $3" >&2; }
}

# ---- Configuration ----
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${ALBA_FALLBACK_MODEL:-gemma4}"

SYSTEM_PROMPT="You are Alba running in fallback mode (Gemma 4 local). Claude is currently unavailable, so you are answering via a local Ollama model. Be helpful and concise. If you cannot answer something well, say so honestly."

# ---- Health checks ----

check_ollama() {
    if ! curl -sf --max-time 5 "$OLLAMA_URL/" > /dev/null 2>&1; then
        alba_log ERROR fallback "Ollama is not running at $OLLAMA_URL"
        return 1
    fi
    return 0
}

check_model() {
    local model_check
    model_check="$(curl -sf --max-time 10 "$OLLAMA_URL/api/tags" 2>/dev/null)" || {
        alba_log ERROR fallback "Failed to query Ollama model list"
        return 1
    }

    if ! echo "$model_check" | jq -e ".models[] | select(.name | startswith(\"$MODEL\"))" > /dev/null 2>&1; then
        alba_log ERROR fallback "Model '$MODEL' not found in Ollama — run: ollama pull $MODEL"
        return 2
    fi
    return 0
}

check_claude_running() {
    local claude_pid
    claude_pid="$(pgrep -f "claude.*--dangerously-skip-permissions" 2>/dev/null | head -1)"
    if [ -n "$claude_pid" ]; then
        local ram_mb
        ram_mb="$(ps -o rss= -p "$claude_pid" 2>/dev/null | awk '{print int($1/1024)}')"
        alba_log WARN fallback "Claude process detected (pid=$claude_pid, ~${ram_mb}MB) — running Ollama alongside may cause memory pressure"
        return 0  # Don't block, just warn
    fi
    return 1  # Claude not running (expected when in fallback)
}

# ---- Query ----

query_ollama() {
    local user_query="$1"

    if [ -z "$user_query" ]; then
        alba_log ERROR fallback "Empty query provided"
        return 3
    fi

    alba_log INFO fallback "Querying Ollama model=$MODEL" "{\"query_length\":${#user_query}}"

    local payload
    payload="$(jq -n \
        --arg model "$MODEL" \
        --arg system "$SYSTEM_PROMPT" \
        --arg user "$user_query" \
        '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $user}], stream: false}'
    )"

    local response
    response="$(curl -sf --max-time 120 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$OLLAMA_URL/api/chat" 2>/dev/null)" || {
        alba_log ERROR fallback "Ollama query failed (timeout or connection error)" "{\"model\":\"$MODEL\"}"
        return 3
    }

    local content
    content="$(echo "$response" | jq -r '.message.content // empty' 2>/dev/null)"

    if [ -z "$content" ]; then
        alba_log ERROR fallback "Ollama returned empty response" "{\"raw_length\":${#response}}"
        return 3
    fi

    alba_log INFO fallback "Ollama query succeeded" "{\"model\":\"$MODEL\",\"response_length\":${#content}}"
    echo "$content"
    return 0
}

# ---- Main ----

main() {
    local subcommand="${1:-}"

    case "$subcommand" in
        status)
            echo "=== Alba Fallback Status ==="
            echo "Ollama URL: $OLLAMA_URL"
            echo "Model: $MODEL"
            echo ""

            if check_ollama; then
                echo "✅ Ollama is running"
            else
                echo "❌ Ollama is not running at $OLLAMA_URL"
                exit 1
            fi

            if check_model; then
                echo "✅ Model '$MODEL' is available"
            else
                echo "❌ Model '$MODEL' not found — run: ollama pull $MODEL"
                exit 2
            fi

            check_claude_running && echo "⚠️  Claude is also running (memory pressure risk)" || echo "ℹ️  Claude is not running (fallback mode expected)"
            echo ""
            echo "Ready for queries."
            ;;

        -h|--help|help)
            echo "Usage: alba-fallback.sh [status|help|\"query\"]"
            echo ""
            echo "  status    Check Ollama and model availability"
            echo "  help      Show this help"
            echo "  \"query\"   Send query to Gemma 4 via Ollama"
            echo ""
            echo "Environment:"
            echo "  OLLAMA_URL=$OLLAMA_URL"
            echo "  ALBA_FALLBACK_MODEL=$MODEL"
            ;;

        "")
            # No argument — check stdin
            if [ ! -t 0 ]; then
                local query
                query="$(cat)"
                check_ollama || exit 1
                check_model || exit 2
                check_claude_running || true
                query_ollama "$query" || exit 3
            else
                echo "Usage: alba-fallback.sh [status|help|\"query\"]" >&2
                echo "  or pipe a query: echo \"question\" | alba-fallback.sh" >&2
                exit 1
            fi
            ;;

        *)
            # Treat argument as query
            check_ollama || exit 1
            check_model || exit 2
            check_claude_running || true
            query_ollama "$subcommand" || exit 3
            ;;
    esac
}

main "$@"
