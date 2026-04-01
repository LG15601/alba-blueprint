#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Agent World — Health Monitor v2.0
# Production-grade system health check with JSON output
# and Telegram alert capability
# ═══════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="$ROOT_DIR/config.json"
OUTPUT_DIR="$SCRIPT_DIR/output"
ALERT_DIR="$SCRIPT_DIR/alerts"
AUDIT_LOG="$SCRIPT_DIR/audit/log.sh"
HEALTH_JSON="$OUTPUT_DIR/health.json"
HEALTH_HUMAN="$OUTPUT_DIR/health.txt"

mkdir -p "$OUTPUT_DIR" "$ALERT_DIR"

# ── Helpers ──────────────────────────────────────────────
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

STATUS_OVERALL="healthy"
CHECKS=()
ALERTS=()

add_check() {
  local name="$1" status="$2" value="$3" detail="${4:-}"
  CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"value\":\"$value\",\"detail\":\"$detail\"}")
  if [[ "$status" == "critical" ]]; then
    STATUS_OVERALL="critical"
    ALERTS+=("🔴 $name: $detail")
  elif [[ "$status" == "warning" && "$STATUS_OVERALL" != "critical" ]]; then
    STATUS_OVERALL="warning"
    ALERTS+=("🟡 $name: $detail")
  fi
}

# ── 1. Disk Space ────────────────────────────────────────
free_gb=$(df -g / | tail -1 | awk '{print $4}')
used_pct=$(df -h / | tail -1 | awk '{gsub(/%/,""); print $5}')
total_gb=$(df -g / | tail -1 | awk '{print $2}')

if (( free_gb < 10 )); then
  add_check "disk" "critical" "${free_gb}GB free" "CRITICAL: Only ${free_gb}GB of ${total_gb}GB free (${used_pct}% used)"
elif (( free_gb < 20 )); then
  add_check "disk" "warning" "${free_gb}GB free" "Low disk: ${free_gb}GB of ${total_gb}GB free (${used_pct}% used)"
else
  add_check "disk" "ok" "${free_gb}GB free" "${used_pct}% used, ${free_gb}GB of ${total_gb}GB free"
fi

# ── 2. Docker ────────────────────────────────────────────
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  container_count=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  unhealthy=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l | tr -d ' ')
  if (( unhealthy > 0 )); then
    names=$(docker ps --filter "health=unhealthy" --format '{{.Names}}' 2>/dev/null | tr '\n' ', ')
    add_check "docker" "warning" "${container_count} containers" "Unhealthy: ${names}"
  else
    add_check "docker" "ok" "${container_count} containers" "All containers healthy"
  fi
else
  add_check "docker" "warning" "not running" "Docker daemon not running"
fi

# ── 3. Middleman ─────────────────────────────────────────
if pgrep -f "middleman" > /dev/null 2>&1; then
  mm_pid=$(pgrep -f 'middleman' | head -1)
  add_check "middleman" "ok" "PID $mm_pid" "Middleman running"
else
  add_check "middleman" "critical" "down" "Middleman NOT running"
fi

# ── 4. Internet Connectivity ────────────────────────────
if curl -s --connect-timeout 5 --max-time 10 https://api.anthropic.com > /dev/null 2>&1; then
  add_check "internet" "ok" "connected" "Anthropic API reachable"
elif curl -s --connect-timeout 5 --max-time 10 https://www.google.com > /dev/null 2>&1; then
  add_check "internet" "warning" "partial" "Google OK but Anthropic unreachable"
else
  add_check "internet" "critical" "offline" "No internet connectivity"
fi

# ── 5. Tailscale ─────────────────────────────────────────
if command -v tailscale &>/dev/null; then
  ts_status=$(tailscale status --json 2>/dev/null | jq -r '.Self.Online // false' 2>/dev/null || echo "false")
  if [[ "$ts_status" == "true" ]]; then
    peer_count=$(tailscale status --json 2>/dev/null | jq '.Peer | length' 2>/dev/null || echo "0")
    add_check "tailscale" "ok" "${peer_count} peers" "Online, ${peer_count} peers connected"
  else
    add_check "tailscale" "warning" "offline" "Tailscale not connected"
  fi
else
  add_check "tailscale" "warning" "not installed" "Tailscale not found"
fi

# ── 6. LaunchAgents (CRON) ───────────────────────────────
alba_agents=$(launchctl list 2>/dev/null | grep "com.alba" | wc -l | tr -d ' ')
running_agents=$(launchctl list 2>/dev/null | grep "com.alba" | awk '$1 != "-"' | wc -l | tr -d ' ')
failed_agents=$(launchctl list 2>/dev/null | grep "com.alba" | awk '$2 != "0" && $2 != "-"' | wc -l | tr -d ' ')

if (( failed_agents > 0 )); then
  failed_names=$(launchctl list 2>/dev/null | grep "com.alba" | awk '$2 != "0" && $2 != "-" {print $3}' | tr '\n' ', ')
  add_check "cron" "warning" "${alba_agents} agents" "Failed: ${failed_names}"
else
  add_check "cron" "ok" "${alba_agents} agents" "All LaunchAgents OK"
fi

# ── 7. Last CRON Runs ───────────────────────────────────
cron_state="$SCRIPT_DIR/cron/state.json"
if [[ -f "$cron_state" ]]; then
  stale_count=0
  stale_names=""
  now_epoch_val=$(now_epoch)
  for agent in $(jq -r 'keys[]' "$cron_state" 2>/dev/null); do
    last_run=$(jq -r ".\"$agent\".last_run_epoch // 0" "$cron_state" 2>/dev/null)
    max_interval=$(jq -r ".\"$agent\".expected_interval_sec // 86400" "$cron_state" 2>/dev/null)
    age=$(( now_epoch_val - last_run ))
    if (( age > max_interval * 2 )); then
      stale_count=$((stale_count + 1))
      stale_names="${stale_names}${agent}, "
    fi
  done
  if (( stale_count > 0 )); then
    add_check "cron_freshness" "warning" "${stale_count} stale" "Overdue: ${stale_names}"
  else
    add_check "cron_freshness" "ok" "all fresh" "All scheduled tasks ran on time"
  fi
else
  add_check "cron_freshness" "ok" "no state yet" "CRON state file not yet created (first run)"
fi

# ── 8. Secret File Permissions ───────────────────────────
secrets_ok=0
secrets_bad=0
for f in ~/.secrets/.env ~/.middleman/secrets.json ~/.middleman/auth/auth.json ~/.config/satori/satori.json; do
  if [[ -f "$f" ]]; then
    perms=$(stat -f "%Lp" "$f")
    if [[ "$perms" == "600" ]]; then
      secrets_ok=$((secrets_ok + 1))
    else
      secrets_bad=$((secrets_bad + 1))
    fi
  fi
done
if (( secrets_bad > 0 )); then
  add_check "secrets" "warning" "${secrets_bad} exposed" "Secret files with wrong permissions"
else
  add_check "secrets" "ok" "${secrets_ok} secured" "All secret files chmod 600"
fi

# ── 9. Memory / CPU ─────────────────────────────────────
mem_pressure=$(memory_pressure 2>/dev/null | grep "System-wide" | awk '{print $NF}' || echo "unknown")
cpu_load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo "0")
add_check "memory" "ok" "$mem_pressure" "Memory pressure: $mem_pressure, Load: $cpu_load"

# ── 10. Agent World Services ────────────────────────────
agent_dirs=0
agent_with_logs=0
for agent_dir in "$ROOT_DIR"/*/; do
  agent_name=$(basename "$agent_dir")
  [[ "$agent_name" == "infra" ]] && continue
  [[ -d "$agent_dir" ]] && agent_dirs=$((agent_dirs + 1))
  [[ -d "$agent_dir/logs" ]] && ls "$agent_dir/logs/"*.jsonl 2>/dev/null | head -1 > /dev/null && agent_with_logs=$((agent_with_logs + 1))
done
add_check "agent_world" "ok" "${agent_dirs} agents" "${agent_with_logs} agents have log activity"

# ── Build JSON Output ────────────────────────────────────
checks_json=$(printf '%s\n' "${CHECKS[@]}" | jq -s '.' 2>/dev/null || echo "[]")
alerts_json=$(printf '%s\n' "${ALERTS[@]}" | jq -R . | jq -s '.' 2>/dev/null || echo "[]")

cat > "$HEALTH_JSON" <<EOF
{
  "timestamp": "$(now_iso)",
  "status": "$STATUS_OVERALL",
  "hostname": "$(hostname)",
  "uptime": "$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')",
  "checks": $checks_json,
  "alerts": $alerts_json,
  "alert_count": ${#ALERTS[@]}
}
EOF

# ── Build Human-Readable Output ─────────────────────────
{
  echo "═══════════════════════════════════════════════════"
  echo "  AGENT WORLD HEALTH CHECK — $(date '+%Y-%m-%d %H:%M')"
  echo "═══════════════════════════════════════════════════"
  echo ""

  status_icon="✅"
  [[ "$STATUS_OVERALL" == "warning" ]] && status_icon="🟡"
  [[ "$STATUS_OVERALL" == "critical" ]] && status_icon="🔴"
  echo "  Overall: $status_icon $STATUS_OVERALL"
  echo ""

  echo "$checks_json" | jq -r '.[] | "  " + (if .status == "ok" then "✅" elif .status == "warning" then "🟡" else "🔴" end) + " " + .name + ": " + .value + " — " + .detail' 2>/dev/null

  if (( ${#ALERTS[@]} > 0 )); then
    echo ""
    echo "  ─── ALERTS ───"
    for alert in "${ALERTS[@]}"; do
      echo "  $alert"
    done
  fi

  echo ""
  echo "═══════════════════════════════════════════════════"
} > "$HEALTH_HUMAN"

# ── Write Telegram Alert if Critical ────────────────────
if [[ "$STATUS_OVERALL" == "critical" ]]; then
  alert_file="$ALERT_DIR/alert-$(date +%s).json"
  cat > "$alert_file" <<EOF
{
  "timestamp": "$(now_iso)",
  "severity": "critical",
  "message": "🚨 AGENT WORLD CRITICAL\\n\\n$(printf '%s\\n' "${ALERTS[@]}" | sed 's/"/\\"/g')",
  "chat_id": "7029673508"
}
EOF
  echo "⚠️  Critical alert written to $alert_file"
fi

# ── Output Mode ──────────────────────────────────────────
if [[ "${1:-}" == "--json" ]]; then
  cat "$HEALTH_JSON"
elif [[ "${1:-}" == "--quiet" ]]; then
  echo "$STATUS_OVERALL"
else
  cat "$HEALTH_HUMAN"
fi

# ── Log this run ─────────────────────────────────────────
if [[ -x "$AUDIT_LOG" ]]; then
  "$AUDIT_LOG" "infra" "health-check" "system" "Status: $STATUS_OVERALL, Alerts: ${#ALERTS[@]}" "success"
fi

exit 0
