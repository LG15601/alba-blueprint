#!/bin/bash
# Alba — Weekly cleanup (Sunday 4 AM via cron)

echo "[$(date)] Starting weekly cleanup..."

# npm cache
npm cache clean --force 2>/dev/null

# Homebrew
brew cleanup --prune=7 2>/dev/null

# pip cache
pip cache purge 2>/dev/null

# Temp files
rm -rf /tmp/playwright* /tmp/*.log /tmp/alba-*.tmp 2>/dev/null

# Old logs
find "$HOME/logs" -name "*.log" -mtime +14 -delete 2>/dev/null
find "$HOME/.alba/logs" -name "*.log" -mtime +14 -delete 2>/dev/null
find "$HOME/.alba/logs/nightly" -name "*.md" -mtime +30 -delete 2>/dev/null

# Docker cleanup (if running)
docker system prune -f 2>/dev/null

# Node modules in temp/old projects
find /tmp -maxdepth 3 -name "node_modules" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null

echo "[$(date)] Cleanup complete. Disk: $(df -h / | awk 'NR==2 {print $5}') used"
