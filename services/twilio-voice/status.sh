#!/usr/bin/env bash
# =============================================================================
# Check status of ElevenLabs Conversational AI + Twilio setup
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
API_BASE="https://api.elevenlabs.io/v1"

# --- Load env ---
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

echo "=== Alba Voice Status ==="
echo ""

# --- Check API key ---
echo "[1] API Key Permissions"
PERM_TEST=$(curl -s -w "\n%{http_code}" "${API_BASE}/convai/agents" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}")
HTTP_CODE=$(echo "$PERM_TEST" | tail -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    AGENT_COUNT=$(echo "$PERM_TEST" | sed '$d' | python3 -c "
import json, sys
data = json.load(sys.stdin)
agents = data.get('agents', [])
print(len(agents))
" 2>/dev/null || echo "?")
    echo "  OK: convai_read works (${AGENT_COUNT} agents found)"
else
    echo "  FAIL: API key missing convai permissions (HTTP $HTTP_CODE)"
    echo "  Fix: Generate new key at https://elevenlabs.io/app/settings/api-keys"
fi

# --- Check Agent ---
echo ""
echo "[2] Agent"
if [[ -z "${ELEVENLABS_AGENT_ID:-}" ]]; then
    echo "  NOT SET: Run setup.sh to create the agent"
else
    AGENT_INFO=$(curl -s "${API_BASE}/convai/agents/${ELEVENLABS_AGENT_ID}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}")
    python3 -c "
import json, sys
data = json.loads('''${ELEVENLABS_AGENT_ID}''')
" 2>/dev/null || true

    AGENT_NAME=$(echo "$AGENT_INFO" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'detail' in data:
    print(f'ERROR: {data[\"detail\"].get(\"message\", \"unknown\")}')
else:
    name = data.get('name', 'unknown')
    lang = data.get('agent_config', {}).get('language', '?')
    voice = data.get('conversational_config', {}).get('tts', {}).get('voice_id', '?')
    model = data.get('conversational_config', {}).get('tts', {}).get('model_id', '?')
    print(f'OK: {name}')
    print(f'    Language: {lang}')
    print(f'    Voice ID: {voice}')
    print(f'    TTS Model: {model}')
    print(f'    Agent ID: ${ELEVENLABS_AGENT_ID}')
" 2>&1)
    echo "  $AGENT_NAME"
fi

# --- Check Phone Number ---
echo ""
echo "[3] Phone Number"
if [[ -z "${ELEVENLABS_PHONE_NUMBER_ID:-}" ]]; then
    echo "  NOT SET: Run setup.sh to import the Twilio number"
else
    PHONE_INFO=$(curl -s "${API_BASE}/convai/phone-numbers/${ELEVENLABS_PHONE_NUMBER_ID}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}")

    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
if 'detail' in data:
    msg = data['detail']
    if isinstance(msg, dict):
        msg = msg.get('message', str(msg))
    print(f'  ERROR: {msg}')
else:
    number = data.get('phone_number', '?')
    label = data.get('label', '?')
    agent = data.get('agent_id', 'none')
    provider = data.get('provider', '?')
    print(f'  OK: {number} ({label})')
    print(f'      Provider: {provider}')
    print(f'      Assigned Agent: {agent}')
    print(f'      Phone ID: ${ELEVENLABS_PHONE_NUMBER_ID}')
" <<< "$PHONE_INFO"
fi

# --- Check Twilio ---
echo ""
echo "[4] Twilio"
TWILIO_CHECK=$(curl -s -u "${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}" \
    "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/IncomingPhoneNumbers/${TWILIO_PHONE_SID}.json" 2>/dev/null)

python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
if 'sid' in data:
    number = data.get('phone_number', '?')
    friendly = data.get('friendly_name', '?')
    voice_url = data.get('voice_url', 'not set')
    voice_method = data.get('voice_method', '?')
    status = data.get('status', '?')
    print(f'  OK: {number} ({friendly})')
    print(f'      Status: {status}')
    print(f'      Voice URL: {voice_url}')
    print(f'      Voice Method: {voice_method}')
else:
    print(f'  ERROR: {data.get(\"message\", \"unknown\")}')
" <<< "$TWILIO_CHECK"

echo ""
echo "=== Summary ==="
echo "Twilio Number:   ${TWILIO_PHONE_NUMBER:-not set}"
echo "Agent ID:        ${ELEVENLABS_AGENT_ID:-not set}"
echo "Phone Number ID: ${ELEVENLABS_PHONE_NUMBER_ID:-not set}"
echo ""
