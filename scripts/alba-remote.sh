#!/bin/bash
# Alba Remote Control
# From MacBook: alba status / alba restart / alba logs
# From iPhone Shortcuts: ssh alba@mac-mini-de-alba "bash ~/bin/alba-remote status"

REMOTE="alba@mac-mini-de-alba"
CMD="${1:-help}"

run() { ssh "$REMOTE" "export PATH=/opt/homebrew/bin:/Users/alba/.nvm/versions/node/v22.22.2/bin:/usr/local/bin:/usr/bin:/bin; export HOME=/Users/alba; $1"; }

case "$CMD" in
  status|s)   run "bash ~/bin/start-alba.sh status" ;;
  restart|r)  run "bash ~/bin/start-alba.sh stop; sleep 2; /opt/homebrew/bin/tmux new-session -d -s alba-launcher 'bash ~/bin/start-alba.sh start'"; sleep 8; run "bash ~/bin/start-alba.sh status" ;;
  stop)       run "bash ~/bin/start-alba.sh stop; /opt/homebrew/bin/tmux kill-session -t alba-launcher 2>/dev/null" ;;
  start)      run "/opt/homebrew/bin/tmux new-session -d -s alba-launcher 'bash ~/bin/start-alba.sh start'"; sleep 8; run "bash ~/bin/start-alba.sh status" ;;
  logs|l)     run "/opt/homebrew/bin/tmux capture-pane -t alba-agent -p 2>/dev/null | tail -30" ;;
  health|h)   run "bash ~/AZW/alba-blueprint/skills/health-check/scripts/health-check.sh" ;;
  check|c)    run "bash ~/AZW/alba-blueprint/scripts/onboard-alba.sh --check" ;;
  *)
    echo "Alba Remote Control"
    echo "  alba status   (s)  — is she running?"
    echo "  alba restart  (r)  — stop + start"
    echo "  alba stop          — kill"
    echo "  alba start         — launch"
    echo "  alba logs     (l)  — last 30 lines"
    echo "  alba health   (h)  — full health check"
    echo "  alba check    (c)  — onboarding check"
    ;;
esac
