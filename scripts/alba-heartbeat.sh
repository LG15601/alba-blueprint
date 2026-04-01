#!/bin/bash
# Alba — Heartbeat check (runs every 15 min via cron)

LOG="/tmp/alba-heartbeat.log"
ALERT_LOG="$HOME/.alba/logs/alerts.log"
mkdir -p "$HOME/.alba/logs"

# Check disk
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
if [ "$DISK_PCT" -ge 95 ]; then
    echo "[$(date)] CRITICAL: Disk at ${DISK_PCT}%" >> "$ALERT_LOG"
elif [ "$DISK_PCT" -ge 90 ]; then
    echo "[$(date)] WARNING: Disk at ${DISK_PCT}%" >> "$ALERT_LOG"
fi

# Check RAM (macOS)
FREE_MEM=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./,""); print $3 * 4096 / 1048576}')

# Check Alba process
ALBA_PID=$(pgrep -f "claude.*channels.*telegram" 2>/dev/null | head -1)
if [ -z "$ALBA_PID" ]; then
    echo "[$(date)] CRITICAL: Alba process not running!" >> "$ALERT_LOG"
else
    ALBA_RAM=$(ps -o rss= -p "$ALBA_PID" 2>/dev/null | awk '{print int($1/1024)}')
    echo "[$(date)] OK: Alba PID $ALBA_PID, ${ALBA_RAM}MB RAM, disk ${DISK_PCT}%" >> "$LOG"
fi

# Check tmux session
if ! tmux has-session -t alba-agent 2>/dev/null; then
    echo "[$(date)] WARNING: tmux session 'alba-agent' not found" >> "$ALERT_LOG"
fi

# Rotate log (keep last 1000 lines)
if [ -f "$LOG" ] && [ $(wc -l < "$LOG") -gt 1000 ]; then
    tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

exit 0
