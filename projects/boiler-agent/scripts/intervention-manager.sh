#!/usr/bin/env bash
# intervention-manager.sh — CLI for managing Guillaume's intervention database
# Used by the boiler-tech bot to persist and query interventions

set -euo pipefail

DB="$HOME/.claude/channels/telegram-guillaume/interventions.db"
TOKEN="8312317492:AAFCrK9phS-aVQgTE6zr-Sl8HRpWKKx3Wpc"
CHAT="8782653250"

usage() {
    echo "Usage: $0 <command> [args]"
    echo "Commands:"
    echo "  start <client> <location>                    Start new intervention"
    echo "  update <id> <field> <value>                  Update intervention field"
    echo "  close <id> <result>                          Close intervention"
    echo "  report <id>                                  Generate intervention report"
    echo "  history [limit]                              List recent interventions"
    echo "  search <client_name>                         Search by client"
    echo "  get <id>                                     Get intervention details"
    echo "  send-history                                 Send history with Telegram inline buttons"
    echo "  send-report <id>                             Send report to Telegram"
    exit 1
}

[[ $# -lt 1 ]] && usage

cmd="$1"; shift

case "$cmd" in
    start)
        client="${1:?Client name required}"
        location="${2:-}"
        id=$(sqlite3 "$DB" "INSERT INTO interventions (client_name, client_location) VALUES ('$(echo "$client" | sed "s/'/''/g")', '$(echo "$location" | sed "s/'/''/g")'); SELECT last_insert_rowid();")
        echo "$id"
        ;;

    update)
        id="${1:?ID required}"; field="${2:?Field required}"; value="${3:?Value required}"
        sqlite3 "$DB" "UPDATE interventions SET ${field} = '$(echo "$value" | sed "s/'/''/g")' WHERE id = $id;"
        echo "OK"
        ;;

    close)
        id="${1:?ID required}"; result="${2:?Result required}"
        sqlite3 "$DB" "UPDATE interventions SET result = '$result', status = 'termine', date_end = datetime('now', 'localtime') WHERE id = $id;"
        echo "OK"
        ;;

    report)
        id="${1:?ID required}"
        sqlite3 -header -separator '|' "$DB" "SELECT * FROM interventions WHERE id = $id;"
        ;;

    history)
        limit="${1:-10}"
        sqlite3 -json "$DB" "SELECT id, date_start, client_name, client_location, boiler_model, fault_codes, result, status FROM interventions ORDER BY date_start DESC LIMIT $limit;"
        ;;

    search)
        query="${1:?Search query required}"
        sqlite3 -json "$DB" "SELECT id, date_start, client_name, client_location, fault_codes, result, status FROM interventions WHERE client_name LIKE '%$(echo "$query" | sed "s/'/''/g")%' ORDER BY date_start DESC;"
        ;;

    get)
        id="${1:?ID required}"
        sqlite3 -json "$DB" "SELECT * FROM interventions WHERE id = $id;"
        ;;

    send-history)
        # Build inline keyboard with recent interventions
        rows=$(sqlite3 -json "$DB" "SELECT id, date_start, client_name, client_location, fault_codes, result FROM interventions ORDER BY date_start DESC LIMIT 20;")

        if [[ "$rows" == "[]" || -z "$rows" ]]; then
            curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
                -H "Content-Type: application/json" \
                -d "{\"chat_id\": \"$CHAT\", \"text\": \"Aucune intervention enregistrée pour le moment.\"}" > /dev/null
            exit 0
        fi

        # Build buttons JSON
        buttons=$(echo "$rows" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
keyboard = []
for r in rows:
    date = r['date_start'][:10] if r.get('date_start') else '?'
    client = r.get('client_name', '?')[:20]
    codes = r.get('fault_codes', '') or ''
    result = r.get('result', 'en_cours') or 'en_cours'
    icon = '✅' if result == 'resolu' else '⏳' if result == 'en_attente_piece' else '👁' if result == 'a_surveiller' else '🔧'
    label = f\"{icon} {date} | {client} | {codes}\"
    keyboard.append([{\"text\": label, \"callback_data\": f\"interv_{r['id']}\"}])
print(json.dumps(keyboard))
")

        curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{
                \"chat_id\": \"$CHAT\",
                \"text\": \"📋 *HISTORIQUE INTERVENTIONS*\n\nAppuie sur une intervention pour voir les détails :\",
                \"parse_mode\": \"MarkdownV2\",
                \"reply_markup\": {\"inline_keyboard\": $buttons}
            }" > /dev/null
        echo "OK"
        ;;

    send-report)
        id="${1:?ID required}"
        data=$(sqlite3 -json "$DB" "SELECT * FROM interventions WHERE id = $id;" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
if not rows:
    print('NOT_FOUND')
    sys.exit(0)
r = rows[0]

def f(key, default='N/C'):
    v = r.get(key)
    return v if v else default

# Escape MarkdownV2 special chars
def esc(s):
    for c in '_*[]()~\`>#+-=|{}.!':
        s = s.replace(c, '\\\\' + c)
    return s

parts_str = ''
if r.get('parts_replaced'):
    try:
        parts = json.loads(r['parts_replaced'])
        parts_str = '\\n'.join([f\"  \\- {esc(p.get('ref',''))} — {esc(p.get('name',''))} x{p.get('qty',1)}\" for p in parts])
    except:
        parts_str = esc(f('parts_replaced'))
else:
    parts_str = 'Aucune'

result_icon = '✅' if f('result') == 'resolu' else '⏳' if f('result') == 'en_attente_piece' else '👁' if f('result') == 'a_surveiller' else '🔧'

msg = f'''📋 *COMPTE RENDU D\\'INTERVENTION \\#{r['id']}*

📅 *Date :* {esc(f('date_start')[:16])}
{('📅 *Fin :* ' + esc(f('date_end','')[:16])) if r.get('date_end') else ''}

👤 *Client :* {esc(f('client_name'))}
📍 *Lieu :* {esc(f('client_location'))}

🔧 *ÉQUIPEMENT*
Marque : {esc(f('boiler_brand'))}
Modèle : {esc(f('boiler_model'))}
N° série : {esc(f('boiler_serial'))}

⚠️ *INTERVENTION*
Codes panne : {esc(f('fault_codes'))}
Symptôme : {esc(f('fault_description'))}
Diagnostic : {esc(f('diagnosis'))}
Solution : {esc(f('solution'))}

📦 *Pièces remplacées :*
{parts_str}

🧪 *Tests :* {esc(f('tests_performed'))}

*RÉSULTAT :* {result_icon} {esc(f('result').replace('_',' ').upper())}

📝 *Observations :*
{esc(f('observations'))}

📅 *Prochaine intervention :* {esc(f('next_intervention'))}'''

print(msg)
")

        if [[ "$data" == "NOT_FOUND" ]]; then
            echo "Intervention #$id not found"
            exit 1
        fi

        curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{
                \"chat_id\": \"$CHAT\",
                \"parse_mode\": \"MarkdownV2\",
                \"text\": $(echo "$data" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
            }" > /dev/null
        echo "OK"
        ;;

    *)
        usage
        ;;
esac
