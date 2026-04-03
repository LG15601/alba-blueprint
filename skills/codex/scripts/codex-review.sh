#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Codex Review — AI-powered code review via Codex CLI
# Wraps `codex review` with pre-flight checks and
# structured error output.
# ═══════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_NAME="codex-review"

# ── Helpers ──────────────────────────────────────────────
err() { echo "[${SCRIPT_NAME}] ERROR: $*" >&2; }
info() { echo "[${SCRIPT_NAME}] $*" >&2; }

# ── Pre-flight checks ───────────────────────────────────
CODEX_BIN="$(command -v codex 2>/dev/null || true)"
if [[ -z "$CODEX_BIN" ]]; then
  err "codex CLI not found on PATH. Install: npm install -g @openai/codex"
  exit 1
fi

if ! "$CODEX_BIN" review --help >/dev/null 2>&1; then
  err "codex review --help failed — check codex installation and auth configuration"
  exit 1
fi

# ── Argument parsing ────────────────────────────────────
ARGS=()

if [[ $# -eq 0 ]]; then
  # Default: review uncommitted changes
  ARGS+=("--uncommitted")
else
  # Pass through all arguments
  ARGS+=("$@")
fi

# ── Execute ──────────────────────────────────────────────
info "Running: codex review ${ARGS[*]}"

if ! "$CODEX_BIN" review "${ARGS[@]}"; then
  err "codex review exited with non-zero status"
  exit 1
fi
