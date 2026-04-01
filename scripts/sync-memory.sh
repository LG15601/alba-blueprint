#!/bin/bash
# Alba — Bidirectional memory sync with VPS
# Runs every 30 minutes via cron

VPS_HOST="${VPS_HOST:-100.95.185.71}"
VPS_USER="${VPS_USER:-clawdbot}"
SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/id_ed25519}"
LOCAL_MEM="$HOME/.claude/projects/-Users-alba/memory/"
REMOTE_MEM="/home/$VPS_USER/.claude/projects/-home-$VPS_USER/memory/"

# Ensure local dir exists
mkdir -p "$LOCAL_MEM"

# VPS → Mac (authoritative)
rsync -az --update \
    -e "ssh -i $SSH_KEY -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new" \
    "$VPS_USER@$VPS_HOST:$REMOTE_MEM" "$LOCAL_MEM" 2>/dev/null

# Mac → VPS (new files only)
rsync -az --ignore-existing \
    -e "ssh -i $SSH_KEY -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new" \
    "$LOCAL_MEM" "$VPS_USER@$VPS_HOST:$REMOTE_MEM" 2>/dev/null

exit 0
