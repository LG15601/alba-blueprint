#!/usr/bin/env bash
# =============================================================================
# One-shot deploy: Fix API key + Create Agent + Import Number + Test Call
# This is the main entry point. Run this once to get everything working.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
API_BASE="https://api.elevenlabs.io/v1"

echo "============================================"
echo " Alba Voice - ElevenLabs + Twilio Deploy"
echo "============================================"
echo ""

# --- Load env ---
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: .env not found at $ENV_FILE"
    exit 1
fi

# --- Step 0: Check API key has convai permissions ---
echo "[0/5] Checking API key permissions..."
PERM_TEST=$(curl -s -w "\n%{http_code}" "${API_BASE}/convai/agents" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}" 2>/dev/null)
HTTP_CODE=$(echo "$PERM_TEST" | tail -1)

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "  Current API key lacks Conversational AI permissions."
    echo ""
    echo "  Opening ElevenLabs dashboard..."
    open "https://elevenlabs.io/app/settings/api-keys" 2>/dev/null || true
    echo ""
    echo "  Create a new API key with these permissions enabled:"
    echo "    [x] Conversational AI: Read (convai_read)"
    echo "    [x] Conversational AI: Write (convai_write)"
    echo "    [x] Text to Speech"
    echo "    [x] Voices: Read"
    echo "    [x] User: Read"
    echo ""
    read -r -p "  Paste the new API key: " NEW_KEY

    if [[ -z "$NEW_KEY" ]]; then
        echo "  No key provided. Aborting."
        exit 1
    fi

    # Test new key
    RETEST=$(curl -s -w "\n%{http_code}" "${API_BASE}/convai/agents" \
        -H "xi-api-key: ${NEW_KEY}" 2>/dev/null)
    RETEST_CODE=$(echo "$RETEST" | tail -1)

    if [[ "$RETEST_CODE" != "200" ]]; then
        echo "  FAIL: New key still lacks permissions. Check scopes and try again."
        exit 1
    fi

    echo "  OK: New key works!"

    # Update both .env files
    sed -i '' "s/^ELEVENLABS_API_KEY=.*/ELEVENLABS_API_KEY=${NEW_KEY}/" "$ENV_FILE"
    ELEVENLABS_API_KEY="$NEW_KEY"

    GLOBAL_ENV="$HOME/.alba/.env"
    if [[ -f "$GLOBAL_ENV" ]]; then
        sed -i '' "s/^ELEVENLABS_API_KEY=.*/ELEVENLABS_API_KEY=${NEW_KEY}/" "$GLOBAL_ENV"
        echo "  Updated global .env too."
    fi
else
    echo "  OK: API key has convai permissions."
fi

# --- Step 1: Create Agent ---
echo ""
echo "[1/5] Creating Alba agent..."

if [[ -n "${ELEVENLABS_AGENT_ID:-}" ]]; then
    # Verify it still exists
    VERIFY=$(curl -s -w "\n%{http_code}" "${API_BASE}/convai/agents/${ELEVENLABS_AGENT_ID}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}")
    V_CODE=$(echo "$VERIFY" | tail -1)
    if [[ "$V_CODE" == "200" ]]; then
        echo "  Agent already exists: ${ELEVENLABS_AGENT_ID}"
    else
        echo "  Agent ID in .env is stale. Creating new agent..."
        ELEVENLABS_AGENT_ID=""
    fi
fi

if [[ -z "${ELEVENLABS_AGENT_ID:-}" ]]; then
    AGENT_RESPONSE=$(curl -s -X POST "${API_BASE}/convai/agents/create" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d @"${SCRIPT_DIR}/agent-config.json")

    AGENT_ID=$(echo "$AGENT_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
aid = data.get('agent_id', '')
if not aid:
    err = data.get('detail', data)
    if isinstance(err, dict):
        err = err.get('message', json.dumps(err))
    print(f'ERROR: {err}', file=sys.stderr)
    sys.exit(1)
print(aid)
" 2>&1)

    if [[ $? -ne 0 ]] || [[ "$AGENT_ID" == ERROR:* ]]; then
        echo "  FAIL creating agent: $AGENT_ID"
        exit 1
    fi

    ELEVENLABS_AGENT_ID="$AGENT_ID"
    sed -i '' "s/^ELEVENLABS_AGENT_ID=.*/ELEVENLABS_AGENT_ID=${AGENT_ID}/" "$ENV_FILE"
    echo "  OK: Created agent ${AGENT_ID}"
fi

# --- Step 2: Import Twilio Phone Number ---
echo ""
echo "[2/5] Importing Twilio phone number..."

if [[ -n "${ELEVENLABS_PHONE_NUMBER_ID:-}" ]]; then
    # Verify it still exists
    VERIFY=$(curl -s -w "\n%{http_code}" "${API_BASE}/convai/phone-numbers/${ELEVENLABS_PHONE_NUMBER_ID}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}")
    V_CODE=$(echo "$VERIFY" | tail -1)
    if [[ "$V_CODE" == "200" ]]; then
        echo "  Phone number already imported: ${ELEVENLABS_PHONE_NUMBER_ID}"
    else
        echo "  Phone number ID in .env is stale. Reimporting..."
        ELEVENLABS_PHONE_NUMBER_ID=""
    fi
fi

if [[ -z "${ELEVENLABS_PHONE_NUMBER_ID:-}" ]]; then
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
pid = data.get('phone_number_id', '')
if not pid:
    err = data.get('detail', data)
    if isinstance(err, dict):
        err = err.get('message', json.dumps(err))
    print(f'ERROR: {err}', file=sys.stderr)
    sys.exit(1)
print(pid)
" 2>&1)

    if [[ $? -ne 0 ]] || [[ "$PHONE_ID" == ERROR:* ]]; then
        echo "  FAIL importing phone: $PHONE_ID"
        exit 1
    fi

    ELEVENLABS_PHONE_NUMBER_ID="$PHONE_ID"
    sed -i '' "s/^ELEVENLABS_PHONE_NUMBER_ID=.*/ELEVENLABS_PHONE_NUMBER_ID=${PHONE_ID}/" "$ENV_FILE"
    echo "  OK: Imported phone ${TWILIO_PHONE_NUMBER} as ${PHONE_ID}"
fi

# --- Step 3: Assign Agent to Phone Number ---
echo ""
echo "[3/5] Linking agent to phone number..."

ASSIGN_RESPONSE=$(curl -s -X PATCH "${API_BASE}/convai/phone-numbers/${ELEVENLABS_PHONE_NUMBER_ID}" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"agent_id\": \"${ELEVENLABS_AGENT_ID}\"}")

ASSIGN_OK=$(echo "$ASSIGN_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'detail' in data:
    err = data['detail']
    if isinstance(err, dict):
        err = err.get('message', json.dumps(err))
    print(f'ERROR: {err}')
    sys.exit(1)
agent = data.get('agent_id', 'none')
print(f'OK: Agent {agent} linked')
" 2>&1)

if [[ $? -ne 0 ]]; then
    echo "  WARNING: $ASSIGN_OK"
else
    echo "  $ASSIGN_OK"
fi

# --- Step 4: Verify everything ---
echo ""
echo "[4/5] Verifying setup..."

# Check agent
AGENT_CHECK=$(curl -s "${API_BASE}/convai/agents/${ELEVENLABS_AGENT_ID}" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}")

python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
name = data.get('name', '?')
lang = data.get('agent_config', {}).get('language', '?')
voice = data.get('conversational_config', {}).get('tts', {}).get('voice_id', '?')
model = data.get('conversational_config', {}).get('tts', {}).get('model_id', '?')
first_msg = data.get('agent_config', {}).get('first_message', '?')[:60]
print(f'  Agent: {name}')
print(f'  Language: {lang} | Voice: {voice} | Model: {model}')
print(f'  First message: {first_msg}...')
" <<< "$AGENT_CHECK" 2>&1

# Check phone
PHONE_CHECK=$(curl -s "${API_BASE}/convai/phone-numbers/${ELEVENLABS_PHONE_NUMBER_ID}" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}")

python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
number = data.get('phone_number', '?')
agent = data.get('agent_id', 'none')
print(f'  Phone: {number} -> Agent: {agent}')
" <<< "$PHONE_CHECK" 2>&1

# --- Step 5: Test call ---
echo ""
echo "[5/5] Ready for test call"
echo ""
echo "============================================"
echo " Setup Complete!"
echo "============================================"
echo ""
echo " Agent ID:        ${ELEVENLABS_AGENT_ID}"
echo " Phone Number ID: ${ELEVENLABS_PHONE_NUMBER_ID}"
echo " Twilio Number:   ${TWILIO_PHONE_NUMBER}"
echo ""
echo " Inbound: Call ${TWILIO_PHONE_NUMBER} to talk to Alba"
echo " Outbound: bash ${SCRIPT_DIR}/call.sh +33666574690"
echo ""

read -r -p "Make a test call to +33666574690 now? (y/n) " DO_CALL
if [[ "$DO_CALL" == "y" ]]; then
    echo ""
    echo "Calling +33666574690..."
    bash "${SCRIPT_DIR}/call.sh" "+33666574690"
fi
