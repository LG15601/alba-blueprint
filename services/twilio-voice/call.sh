#!/usr/bin/env bash
# =============================================================================
# Make an outbound call via ElevenLabs + Twilio
# Usage: bash call.sh +33666574690
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

# --- Parse args ---
TO_NUMBER="${1:-}"
if [[ -z "$TO_NUMBER" ]]; then
    echo "Usage: bash call.sh <phone_number>"
    echo "  phone_number: E.164 format (e.g., +33666574690)"
    exit 1
fi

# Validate E.164 format
if [[ ! "$TO_NUMBER" =~ ^\+[0-9]{8,15}$ ]]; then
    echo "ERROR: Phone number must be in E.164 format (e.g., +33666574690)"
    exit 1
fi

# --- Validate required vars ---
for var in ELEVENLABS_API_KEY ELEVENLABS_AGENT_ID ELEVENLABS_PHONE_NUMBER_ID; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var is not set. Run setup.sh first."
        exit 1
    fi
done

echo "=== Outbound Call ==="
echo "From: ${TWILIO_PHONE_NUMBER:-unknown}"
echo "To:   ${TO_NUMBER}"
echo "Agent: ${ELEVENLABS_AGENT_ID}"
echo ""

# --- Make the call ---
echo "Initiating call..."
CALL_RESPONSE=$(curl -s -X POST "${API_BASE}/convai/twilio/outbound-call" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"agent_id\": \"${ELEVENLABS_AGENT_ID}\",
        \"agent_phone_number_id\": \"${ELEVENLABS_PHONE_NUMBER_ID}\",
        \"to_number\": \"${TO_NUMBER}\"
    }")

# --- Parse response ---
python3 -c "
import json, sys

data = json.loads('''${CALL_RESPONSE}''')

if data.get('success'):
    print('Call initiated successfully!')
    if data.get('conversation_id'):
        print(f'  Conversation ID: {data[\"conversation_id\"]}')
    if data.get('call_sid'):
        print(f'  Call SID: {data[\"call_sid\"]}')
    print()
    print('The phone should ring now. Alba will speak when answered.')
elif 'detail' in data:
    detail = data['detail']
    if isinstance(detail, dict):
        print(f'ERROR: {detail.get(\"message\", json.dumps(detail))}')
    else:
        print(f'ERROR: {detail}')
else:
    print(f'Response: {json.dumps(data, indent=2)}')
"

echo ""
echo "Monitor the call at: https://elevenlabs.io/app/conversational-ai/history"
