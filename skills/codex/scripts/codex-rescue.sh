#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Codex Rescue — Autonomous fix execution via Codex CLI
# Wraps `codex exec --full-auto` with pre-flight checks
# and structured error output.
# ═══════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_NAME="codex-rescue"

# ── Helpers ──────────────────────────────────────────────
err() { echo "[${SCRIPT_NAME}] ERROR: $*" >&2; }
info() { echo "[${SCRIPT_NAME}] $*" >&2; }

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME [--dir <path>] <task description>

Run an autonomous fix via Codex in full-auto mode.

Options:
  --dir <path>    Working directory for the fix (passed as --add-dir to codex)

Examples:
  $SCRIPT_NAME "fix the failing unit test in auth.test.ts"
  $SCRIPT_NAME --dir ./packages/api "fix the broken import"
EOF
  exit 1
}

# ── Pre-flight checks ───────────────────────────────────
CODEX_BIN="$(command -v codex 2>/dev/null || true)"
if [[ -z "$CODEX_BIN" ]]; then
  err "codex CLI not found on PATH. Install: npm install -g @openai/codex"
  exit 1
fi

if ! "$CODEX_BIN" --help >/dev/null 2>&1; then
  err "codex --help failed — check codex installation and auth configuration"
  exit 1
fi

# ── Argument parsing ────────────────────────────────────
ADD_DIR=""
TASK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ $# -lt 2 ]]; then
        err "--dir requires a path argument"
        exit 1
      fi
      ADD_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      TASK="$1"
      shift
      ;;
  esac
done

if [[ -z "$TASK" ]]; then
  err "No task description provided"
  usage
fi

# ── Build command ────────────────────────────────────────
CMD_ARGS=(exec --full-auto)

if [[ -n "$ADD_DIR" ]]; then
  CMD_ARGS+=(--add-dir "$ADD_DIR")
fi

CMD_ARGS+=("$TASK")

# ── Execute ──────────────────────────────────────────────
info "Running: codex ${CMD_ARGS[*]}"

exec "$CODEX_BIN" "${CMD_ARGS[@]}"
