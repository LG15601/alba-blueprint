#!/usr/bin/env bash
# start-guillaume-bot.sh — Launch the boiler technician bot for Guillaume
# This runs a separate Claude Code session connected to Guillaume's Telegram bot
# The bot uses the boiler-tech skill for heating system troubleshooting

set -euo pipefail

STATE_DIR="$HOME/.claude/channels/telegram-guillaume"
ENV_FILE="$STATE_DIR/.env"

# Verify token is configured
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: No bot token configured."
    echo "Run: echo 'TELEGRAM_BOT_TOKEN=<token>' > $ENV_FILE && chmod 600 $ENV_FILE"
    exit 1
fi

# Source token
source "$ENV_FILE"
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    echo "ERROR: TELEGRAM_BOT_TOKEN is empty in $ENV_FILE"
    exit 1
fi

echo "Starting Guillaume's boiler tech bot..."
echo "State dir: $STATE_DIR"
echo "Bot ready for connections."

# Launch Claude Code with Guillaume's Telegram channel
export TELEGRAM_STATE_DIR="$STATE_DIR"
exec claude \
    --channels "plugin:telegram@claude-plugins-official" \
    -p "Tu es un assistant technique spécialisé en dépannage de chaudières biomasse. Tu assistes Guillaume, technicien chauffagiste sur le terrain. Utilise le skill /boiler-tech pour diagnostiquer les pannes. Réponds toujours en français. Quand Guillaume t'envoie une photo d'écran de chaudière, analyse les codes erreur visibles. Quand il te dit que l'intervention est terminée, génère un compte rendu professionnel. Sois concis, pratique, et pense toujours à la sécurité."
