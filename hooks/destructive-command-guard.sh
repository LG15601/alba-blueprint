#!/bin/bash
# Alba — Destructive Command Guard (PreToolUse: Bash)
# Path-aware tiered enforcement: block catastrophic, warn risky, allow safe.
# Config: config/destructive-commands.json (relative to script dir)
# Exit 2 = deny, Exit 0 = allow (with optional warning context).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/destructive-commands.json"

# --- Read hook input ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- Load config (fall back to hardcoded if missing/broken) ---
BLOCK_PATTERNS=()
BLOCK_IDS=()
BLOCK_REASONS=()
WARN_PATTERNS=()
WARN_IDS=()
WARN_REASONS=()

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi
  # Validate JSON is parseable
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    return 1
  fi

  while IFS= read -r line; do
    local pat id reason
    pat=$(echo "$line" | awk -F'\\|\\|\\|' '{print $1}')
    id=$(echo "$line" | awk -F'\\|\\|\\|' '{print $2}')
    reason=$(echo "$line" | awk -F'\\|\\|\\|' '{print $3}')
    BLOCK_PATTERNS+=("$pat")
    BLOCK_IDS+=("$id")
    BLOCK_REASONS+=("$reason")
  done < <(jq -r '.tiers.block.patterns[] | "\(.pattern)|||\(.id)|||\(.reason)"' "$CONFIG_FILE" 2>/dev/null)

  while IFS= read -r line; do
    local pat id reason
    pat=$(echo "$line" | awk -F'\\|\\|\\|' '{print $1}')
    id=$(echo "$line" | awk -F'\\|\\|\\|' '{print $2}')
    reason=$(echo "$line" | awk -F'\\|\\|\\|' '{print $3}')
    WARN_PATTERNS+=("$pat")
    WARN_IDS+=("$id")
    WARN_REASONS+=("$reason")
  done < <(jq -r '.tiers.warn.patterns[] | "\(.pattern)|||\(.id)|||\(.reason)"' "$CONFIG_FILE" 2>/dev/null)

  return 0
}

load_hardcoded() {
  # Fail-closed hardcoded fallback — block obvious catastrophic commands
  BLOCK_PATTERNS=(
    'rm\s+-[^\s]*r[^\s]*f[^\s]*\s+/\s*$'
    'rm\s+-[^\s]*r[^\s]*f[^\s]*\s+/\*'
    'rm\s+-[^\s]*r[^\s]*f[^\s]*\s+~/?\s*$'
    'sudo\s+rm\s+-[^\s]*r[^\s]*f'
    ':\(\)\{\s*:\|:&\s*\};:'
    'mkfs\.'
    'dd\s+if=.*of=/dev/[sh]d'
    'chmod\s+-R\s+777\s+/\s*$'
  )
  BLOCK_IDS=("rm_root" "rm_root_glob" "rm_home" "sudo_rm_rf" "fork_bomb" "format_disk" "dd_overwrite" "chmod_root")
  BLOCK_REASONS=(
    "Recursive force-delete from filesystem root"
    "Recursive force-delete of all root contents"
    "Recursive force-delete of home directory"
    "Privileged recursive force-delete"
    "Fork bomb"
    "Filesystem format"
    "Direct disk overwrite"
    "Recursive open permissions on filesystem root"
  )

  WARN_PATTERNS=(
    'git\s+push.*--force'
    'git\s+reset\s+--hard'
    'DROP\s+(TABLE|DATABASE)'
    'DELETE\s+FROM'
    'truncate\s+'
    'kill\s+-9'
    'docker\s+system\s+prune\s+-a'
    'sudo\s+'
  )
  WARN_IDS=("force_push" "hard_reset" "drop_sql" "delete_sql" "truncate" "kill_9" "docker_prune" "sudo")
  WARN_REASONS=(
    "Force push overwrites remote history"
    "Hard reset discards uncommitted changes"
    "SQL schema destruction"
    "SQL data deletion"
    "Data truncation"
    "Forced process termination"
    "Remove all unused Docker resources"
    "Elevated privileges — verify necessity"
  )
}

if ! load_config; then
  load_hardcoded
fi

# --- Path-aware rm analysis ---
# Returns 0 if the rm command targets a dangerous path (should block).
# Returns 1 if targets are safe (project-relative, /tmp subdir, etc.).
rm_targets_dangerous_path() {
  local cmd="$1"

  # Extract everything after 'rm' and its flags
  # Strip the rm command and flags (args starting with -)
  local args
  args=$(echo "$cmd" | sed -E 's/^[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+//' | sed -E 's/-[[:alpha:]]+[[:space:]]*//g' | sed -E 's/^[[:space:]]+//' | sed -E 's/[[:space:]]+$//')

  # Strip optional quotes around the path
  args=$(echo "$args" | sed -E "s/^['\"]//;s/['\"]$//")

  # If empty after stripping, treat as dangerous (can't determine target)
  if [ -z "$args" ]; then
    return 0
  fi

  # If target contains unexpanded variable ($VAR, ${VAR}), it's unknown — warn only
  if echo "$args" | grep -qE '\$'; then
    return 2  # Special: unknown target, use warn instead of block
  fi

  # Dangerous paths — filesystem root, home dir, system directories
  # Check against blocked prefixes
  local dangerous_prefixes=(
    "^/\*?$"          # / or /*
    "^~/?$"           # ~ or ~/
    "^/etc"           # /etc and subdirs
    "^/var"           # /var and subdirs
    "^/usr"           # /usr and subdirs
    "^/bin"           # /bin and subdirs
    "^/sbin"          # /sbin and subdirs
    "^/lib"           # /lib and subdirs
    "^/boot"          # /boot and subdirs
    "^/System"        # macOS system
    "^/Applications"  # macOS applications
    "^/Library"       # macOS library
  )

  for prefix in "${dangerous_prefixes[@]}"; do
    if echo "$args" | grep -qE "$prefix"; then
      return 0  # Dangerous
    fi
  done

  # Safe paths: relative (./anything, anything without leading /), /tmp subdirs
  return 1
}

# --- Pre-check: rm with variable targets (can't resolve statically) ---
if echo "$COMMAND" | grep -qiE 'rm\s+-[^\s]*r[^\s]*f.*\$'; then
  cat <<EOF
{"hookSpecificOutput":{"additionalContext":"WARNING: rm -rf with unresolvable variable in target. Cannot verify safety — proceed with caution."}}
EOF
  exit 0
fi

# --- Check block tier ---
for i in "${!BLOCK_PATTERNS[@]}"; do
  pattern="${BLOCK_PATTERNS[$i]}"
  id="${BLOCK_IDS[$i]}"
  reason="${BLOCK_REASONS[$i]}"

  if echo "$COMMAND" | grep -qiE "$pattern"; then
    # For rm-related patterns, do path-aware analysis
    if [[ "$id" == rm_* ]]; then
      rm_targets_dangerous_path "$COMMAND"
      path_result=$?
      if [ $path_result -eq 1 ]; then
        # Safe target — allow
        continue
      elif [ $path_result -eq 2 ]; then
        # Unknown target (variable) — warn instead of block
        cat <<EOF
{"hookSpecificOutput":{"additionalContext":"WARNING: rm command with unresolvable target variable detected. Cannot verify safety — proceed with caution."}}
EOF
        exit 0
      fi
    fi

    # Block
    cat <<EOF
{"hookSpecificOutput":{"decision":"block","reason":"BLOCKED [$id]: $reason. This command is never allowed in autonomous mode."}}
EOF
    exit 2
  fi
done

# --- Check warn tier ---
for i in "${!WARN_PATTERNS[@]}"; do
  pattern="${WARN_PATTERNS[$i]}"
  id="${WARN_IDS[$i]}"
  reason="${WARN_REASONS[$i]}"

  if echo "$COMMAND" | grep -qiE "$pattern"; then
    cat <<EOF
{"hookSpecificOutput":{"additionalContext":"WARNING [$id]: $reason. Proceeding, but verify this is intentional."}}
EOF
    exit 0
  fi
done

# No match — allow
exit 0
