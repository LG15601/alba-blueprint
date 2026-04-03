#!/usr/bin/env bash
# =============================================================================
# Fix ElevenLabs API Key Permissions
# Opens the dashboard and guides through creating a proper key
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

echo "=== Fix ElevenLabs API Key ==="
echo ""
echo "Your current API key is missing Conversational AI permissions."
echo ""
echo "Steps to fix:"
echo ""
echo "1. Opening ElevenLabs API key settings in your browser..."
open "https://elevenlabs.io/app/settings/api-keys" 2>/dev/null || echo "   Go to: https://elevenlabs.io/app/settings/api-keys"

echo ""
echo "2. Click '+ Create API Key'"
echo ""
echo "3. Name it: 'alba-convai-full'"
echo ""
echo "4. Under permissions, enable ALL of these:"
echo "   - Conversational AI: Read"
echo "   - Conversational AI: Write"
echo "   - Conversational AI: Call"
echo "   - Text to Speech (for voice synthesis)"
echo "   - Voices: Read"
echo "   - User: Read"
echo ""
echo "5. Click 'Create' and copy the new key"
echo ""

read -r -p "Paste your new API key here: " NEW_KEY

if [[ -z "$NEW_KEY" ]]; then
    echo "No key provided. Aborting."
    exit 1
fi

if [[ ! "$NEW_KEY" =~ ^sk_ ]]; then
    echo "WARNING: Key doesn't start with 'sk_'. Are you sure this is correct?"
    read -r -p "Continue? (y/n) " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo "Aborting."
        exit 1
    fi
fi

# Test the new key
echo ""
echo "Testing new key..."
TEST=$(curl -s -w "\n%{http_code}" "https://api.elevenlabs.io/v1/convai/agents" \
    -H "xi-api-key: ${NEW_KEY}")
HTTP_CODE=$(echo "$TEST" | tail -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "  OK: New key has convai_read permission"
else
    BODY=$(echo "$TEST" | sed '$d')
    ERROR=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('detail',{}).get('message','unknown'))" 2>/dev/null || echo "$BODY")
    echo "  FAIL: $ERROR"
    echo "  The new key still doesn't have the right permissions."
    echo "  Make sure you enabled Conversational AI permissions."
    exit 1
fi

# Update .env file
echo "Updating ${ENV_FILE}..."
if [[ -f "$ENV_FILE" ]]; then
    sed -i '' "s/^ELEVENLABS_API_KEY=.*/ELEVENLABS_API_KEY=${NEW_KEY}/" "$ENV_FILE"
    echo "  OK: .env updated"
else
    echo "ELEVENLABS_API_KEY=${NEW_KEY}" > "$ENV_FILE"
    echo "  OK: .env created"
fi

# Also update the global .alba/.env
GLOBAL_ENV="$HOME/.alba/.env"
if [[ -f "$GLOBAL_ENV" ]]; then
    echo "Updating ${GLOBAL_ENV}..."
    sed -i '' "s/^ELEVENLABS_API_KEY=.*/ELEVENLABS_API_KEY=${NEW_KEY}/" "$GLOBAL_ENV"
    echo "  OK: Global .env updated"
fi

echo ""
echo "API key updated. Now run setup.sh to create the agent:"
echo "  bash ${SCRIPT_DIR}/setup.sh"
