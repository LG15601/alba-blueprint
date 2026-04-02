#!/usr/bin/env bash
# pre-restart-gate.sh — Check last CI run status before allowing Alba restart.
# Exit 0 = allow restart. Exit 1 = block restart.
# Fail-open: any error (no gh, no network, no runs) → allow restart (D005).
# All diagnostic output goes to stderr so stdout stays clean for callers.

set -o pipefail

WORKFLOW_FILE="test.yml"

usage() {
  cat >&2 <<'EOF'
Usage: pre-restart-gate.sh [OPTIONS]

Check the last GitHub Actions CI run and gate restarts on failure.

Options:
  --force   Bypass the gate (always allow restart)
  --help    Show this help message

Exit codes:
  0  Allow restart (CI passed, no data, or error — fail-open)
  1  Block restart (last CI run failed)
EOF
}

# --- Parse flags ---
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --help)  usage; exit 0 ;;
    --force) FORCE=true ;;
    *)       echo "Unknown option: $arg" >&2; usage; exit 0 ;;
  esac
done

if "$FORCE"; then
  echo "[pre-restart-gate] --force: bypassing CI gate check" >&2
  exit 0
fi

# --- Check gh availability ---
if ! command -v gh >/dev/null 2>&1; then
  echo "[pre-restart-gate] gh CLI not found — fail-open, allowing restart" >&2
  exit 0
fi

# --- Query last CI run ---
run_json=$(gh run list --workflow="$WORKFLOW_FILE" --limit=1 --json conclusion 2>&1)
gh_exit=$?

if [ "$gh_exit" -ne 0 ]; then
  echo "[pre-restart-gate] gh run list failed (exit $gh_exit) — fail-open, allowing restart" >&2
  echo "[pre-restart-gate] output: $run_json" >&2
  exit 0
fi

# --- Parse conclusion ---
# gh returns a JSON array, e.g. [{"conclusion":"success"}] or []
if [ -z "$run_json" ] || [ "$run_json" = "[]" ]; then
  echo "[pre-restart-gate] No CI runs found — fail-open, allowing restart" >&2
  exit 0
fi

# Extract conclusion — use python if available, fall back to grep/sed
conclusion=""
if command -v python3 >/dev/null 2>&1; then
  conclusion=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d[0].get('conclusion','') if d else '')" <<< "$run_json" 2>/dev/null)
elif command -v jq >/dev/null 2>&1; then
  conclusion=$(echo "$run_json" | jq -r '.[0].conclusion // empty' 2>/dev/null)
else
  # Fallback: simple text extraction
  conclusion=$(echo "$run_json" | grep -o '"conclusion":"[^"]*"' | head -1 | sed 's/"conclusion":"//;s/"//')
fi

if [ -z "$conclusion" ]; then
  echo "[pre-restart-gate] Could not parse CI conclusion — fail-open, allowing restart" >&2
  exit 0
fi

# --- Gate decision ---
case "$conclusion" in
  success)
    echo "[pre-restart-gate] Last CI run: success — allowing restart" >&2
    exit 0
    ;;
  failure)
    echo "[pre-restart-gate] ⚠ Last CI run: FAILURE — blocking restart" >&2
    echo "[pre-restart-gate] Fix failing tests or use --force to bypass" >&2
    exit 1
    ;;
  *)
    # in_progress, cancelled, skipped, etc. — fail-open
    echo "[pre-restart-gate] Last CI run: $conclusion — fail-open, allowing restart" >&2
    exit 0
    ;;
esac
