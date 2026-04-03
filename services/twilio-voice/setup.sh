#!/usr/bin/env bash
# =============================================================================
# ElevenLabs Conversational AI + Twilio Setup
# Creates the Alba agent and imports the Twilio phone number
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
AGENT_CONFIG="${SCRIPT_DIR}/agent-config.json"
API_BASE="https://api.elevenlabs.io/v1"

# --- Load env ---
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# --- Validate required vars ---
for var in ELEVENLABS_API_KEY TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_PHONE_NUMBER; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var is not set in .env"
        exit 1
    fi
done

echo "=== ElevenLabs + Twilio Setup ==="
echo ""

# --- Step 0: Test API key permissions ---
echo "[0/4] Testing API key permissions..."
PERM_TEST=$(curl -s -w "\n%{http_code}" "${API_BASE}/convai/agents" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}")
HTTP_CODE=$(echo "$PERM_TEST" | tail -1)
BODY=$(echo "$PERM_TEST" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "  OK: API key has convai_read permission"
else
    ERROR_MSG=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('detail',{}).get('message','unknown'))" 2>/dev/null || echo "$BODY")
    echo "  FAIL: $ERROR_MSG"
    echo ""
    echo "  Your API key needs these permissions:"
    echo "    - convai_read   (read conversational AI agents)"
    echo "    - convai_write  (create/update agents)"
    echo "    - convai_call   (make outbound calls)"
    echo ""
    echo "  To fix:"
    echo "    1. Go to https://elevenlabs.io/app/settings/api-keys"
    echo "    2. Create a new API key"
    echo "    3. Enable ALL 'Conversational AI' permissions"
    echo "    4. Update ELEVENLABS_API_KEY in ${ENV_FILE}"
    echo "    5. Re-run this script"
    exit 1
fi

# --- Step 1: Create Agent ---
echo "[1/4] Creating Alba agent..."

if [[ -n "${ELEVENLABS_AGENT_ID:-}" ]]; then
    echo "  Agent ID already set: ${ELEVENLABS_AGENT_ID}"
    echo "  Skipping creation. Delete ELEVENLABS_AGENT_ID from .env to recreate."
else
    AGENT_RESPONSE=$(curl -s -X POST "${API_BASE}/convai/agents/create" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d @"${AGENT_CONFIG}")

    AGENT_ID=$(echo "$AGENT_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
agent_id = data.get('agent_id', '')
if not agent_id:
    print('ERROR: ' + json.dumps(data), file=sys.stderr)
    sys.exit(1)
print(agent_id)
" 2>&1)

    if [[ "$AGENT_ID" == ERROR:* ]]; then
        echo "  FAIL: Could not create agent"
        echo "  $AGENT_ID"
        exit 1
    fi

    echo "  OK: Agent created with ID: ${AGENT_ID}"

    # Save agent ID to .env
    if grep -q "^ELEVENLABS_AGENT_ID=" "$ENV_FILE"; then
        sed -i '' "s/^ELEVENLABS_AGENT_ID=.*/ELEVENLABS_AGENT_ID=${AGENT_ID}/" "$ENV_FILE"
    else
        echo "ELEVENLABS_AGENT_ID=${AGENT_ID}" >> "$ENV_FILE"
    fi
    ELEVENLABS_AGENT_ID="$AGENT_ID"
fi

# --- Step 2: Import Twilio Phone Number ---
echo "[2/4] Importing Twilio phone number..."

if [[ -n "${ELEVENLABS_PHONE_NUMBER_ID:-}" ]]; then
    echo "  Phone Number ID already set: ${ELEVENLABS_PHONE_NUMBER_ID}"
    echo "  Skipping import. Delete ELEVENLABS_PHONE_NUMBER_ID from .env to reimport."
else
    PHONE_RESPONSE=$(curl -s -X POST "${API_BASE}/convai/phone-numbers" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"phone_number\": \"${TWILIO_PHONE_NUMBER}\",
            \"label\": \"Alba - Orchestra Intelligence\",
            \"provider\": \"twilio\",
            \"sid\": \"${TWILIO_ACCOUNT_SID}\",
            \"token\": \"${TWILIO_AUTH_TOKEN}\"
        }")

    PHONE_ID=$(echo "$PHONE_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
phone_id = data.get('phone_number_id', '')
if not phone_id:
    print('ERROR: ' + json.dumps(data), file=sys.stderr)
    sys.exit(1)
print(phone_id)
" 2>&1)

    if [[ "$PHONE_ID" == ERROR:* ]]; then
        echo "  FAIL: Could not import phone number"
        echo "  $PHONE_ID"
        exit 1
    fi

    echo "  OK: Phone number imported with ID: ${PHONE_ID}"

    # Save phone number ID to .env
    if grep -q "^ELEVENLABS_PHONE_NUMBER_ID=" "$ENV_FILE"; then
        sed -i '' "s/^ELEVENLABS_PHONE_NUMBER_ID=.*/ELEVENLABS_PHONE_NUMBER_ID=${PHONE_ID}/" "$ENV_FILE"
    else
        echo "ELEVENLABS_PHONE_NUMBER_ID=${PHONE_ID}" >> "$ENV_FILE"
    fi
    ELEVENLABS_PHONE_NUMBER_ID="$PHONE_ID"
fi

# --- Step 3: Assign Agent to Phone Number ---
echo "[3/4] Assigning agent to phone number..."

ASSIGN_RESPONSE=$(curl -s -X PATCH "${API_BASE}/convai/phone-numbers/${ELEVENLABS_PHONE_NUMBER_ID}" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"agent_id\": \"${ELEVENLABS_AGENT_ID}\"}")

ASSIGN_CHECK=$(echo "$ASSIGN_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'detail' in data:
    print('ERROR: ' + data['detail'].get('message', json.dumps(data['detail'])))
else:
    agent = data.get('agent_id', 'none')
    print(f'OK: Agent {agent} assigned to phone number')
" 2>&1)

echo "  $ASSIGN_CHECK"
if [[ "$ASSIGN_CHECK" == ERROR:* ]]; then
    echo "  WARNING: Could not assign agent. You may need to do this manually."
fi

# --- Step 4: Verify Setup ---
echo "[4/4] Verifying setup..."

VERIFY=$(curl -s "${API_BASE}/convai/agents/${ELEVENLABS_AGENT_ID}" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}")

AGENT_NAME=$(echo "$VERIFY" | python3 -c "
import json, sys
data = json.load(sys.stdin)
name = data.get('name', 'unknown')
lang = data.get('agent_config', {}).get('language', 'unknown')
voice = data.get('conversational_config', {}).get('tts', {}).get('voice_id', 'unknown')
print(f'Agent: {name} | Language: {lang} | Voice: {voice}')
" 2>&1)

echo "  $AGENT_NAME"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Agent ID:        ${ELEVENLABS_AGENT_ID}"
echo "Phone Number ID: ${ELEVENLABS_PHONE_NUMBER_ID}"
echo "Twilio Number:   ${TWILIO_PHONE_NUMBER}"
echo ""
echo "Inbound calls to ${TWILIO_PHONE_NUMBER} will now be handled by Alba."
echo ""
echo "To make an outbound test call:"
echo "  bash ${SCRIPT_DIR}/call.sh +33666574690"
echo ""
