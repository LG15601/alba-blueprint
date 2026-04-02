#!/bin/bash
# ==========================================================
# Alba Army — Morning Report Compiler
# Reads completed/ and failed/, generates French markdown report
# Usage: compile-report.sh [YYYY-MM-DD]
# ==========================================================
set -u

# ---- PATH for launchd ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
ARMY_BASE="$HOME/.alba/army"
COMPLETED_DIR="${ARMY_BASE}/completed"
FAILED_DIR="${ARMY_BASE}/failed"
REPORTS_DIR="${ARMY_BASE}/reports"
LOG_FILE="${ARMY_BASE}/logs/compile-report.log"
LOG_TAG="army-report"

# Target date (default: today)
REPORT_DATE="${1:-$(date '+%Y-%m-%d')}"
REPORT_FILE="${REPORTS_DIR}/${REPORT_DATE}.md"

# ---- Ensure directories ----
mkdir -p "$REPORTS_DIR" "${ARMY_BASE}/logs"

# ---- Logging ----
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1" 2>/dev/null
    echo "$msg" >> "$LOG_FILE"
}

log "Compiling report for ${REPORT_DATE}"

# ---- Generate report via Python ----
export REPORT_DATE
export ARMY_BASE
export REPORT_FILE

python3 << 'PYEOF'
import json
import os
import glob
from datetime import datetime
from collections import defaultdict

report_date = os.environ["REPORT_DATE"]
army_base = os.environ["ARMY_BASE"]
report_file = os.environ["REPORT_FILE"]
completed_dir = os.path.join(army_base, "completed")
failed_dir = os.path.join(army_base, "failed")

# Category display names (French)
category_names = {
    "email": "Email",
    "prospection": "Prospection",
    "content": "Contenu",
    "code": "Code & Dev",
    "client": "Clients",
    "research": "Recherche",
    "personal": "Personnel"
}

def load_tasks(directory):
    """Load task JSON files matching the report date."""
    tasks = []
    for filepath in sorted(glob.glob(os.path.join(directory, "*.json"))):
        try:
            with open(filepath) as f:
                task = json.load(f)
            for date_field in ["dispatched_at", "completed_at", "created_at"]:
                dt = task.get(date_field) or ""
                if dt.startswith(report_date):
                    tasks.append(task)
                    break
        except (json.JSONDecodeError, IOError):
            continue
    return tasks

completed_tasks = load_tasks(completed_dir)
failed_tasks = load_tasks(failed_dir)
total_tasks = len(completed_tasks) + len(failed_tasks)

if total_tasks == 0:
    with open(report_file, "w") as f:
        f.write(f"# Rapport Nuit Alba - {report_date}\n\n")
        f.write("Aucune tache executee cette nuit.\n")
    print(f"EMPTY: no tasks for {report_date}")
    exit(0)

# Group by category
completed_by_cat = defaultdict(list)
failed_by_cat = defaultdict(list)
for t in completed_tasks:
    completed_by_cat[t.get("category", "other")].append(t)
for t in failed_tasks:
    failed_by_cat[t.get("category", "other")].append(t)

all_categories = sorted(set(list(completed_by_cat.keys()) + list(failed_by_cat.keys())))
success_count = len(completed_tasks)
fail_count = len(failed_tasks)
success_rate = (success_count / total_tasks * 100) if total_tasks > 0 else 0

# Build report
lines = []
lines.append(f"# Rapport Nuit Alba - {report_date}")
lines.append("")
lines.append(f"**Bilan:** {success_count}/{total_tasks} taches reussies ({success_rate:.0f}%)")
lines.append("")
lines.append("---")
lines.append("")

for cat in all_categories:
    cat_display = category_names.get(cat, cat.title())
    cat_completed = completed_by_cat.get(cat, [])
    cat_failed = failed_by_cat.get(cat, [])
    cat_total = len(cat_completed) + len(cat_failed)

    lines.append(f"## {cat_display} ({len(cat_completed)}/{cat_total})")
    lines.append("")

    for t in cat_completed:
        priority = t.get("priority", "P2")
        raw = t.get("raw_input", "Sans description")
        if len(raw) > 120:
            raw = raw[:117] + "..."
        result = t.get("result", {})
        summary = ""
        if isinstance(result, dict):
            summary = result.get("summary", "")
        elif result:
            summary = str(result)[:200]
        lines.append(f"- [x] [{priority}] {raw}")
        if summary:
            s = summary.replace("\n", " ").strip()
            if len(s) > 200:
                s = s[:197] + "..."
            lines.append(f"  > {s}")

    for t in cat_failed:
        priority = t.get("priority", "P2")
        raw = t.get("raw_input", "Sans description")
        if len(raw) > 120:
            raw = raw[:117] + "..."
        error = t.get("error", "Erreur inconnue")
        if len(error) > 150:
            error = error[:147] + "..."
        retries = t.get("retry_count", 0)
        retry_note = f" ({retries} tentative(s))" if retries > 0 else ""
        lines.append(f"- [ ] [{priority}] {raw}{retry_note}")
        lines.append(f"  > Echec: {error}")

    lines.append("")

# Actions Requises
lines.append("---")
lines.append("")
lines.append("## Actions Requises")
lines.append("")

actions_found = False
for t in failed_tasks:
    priority = t.get("priority", "P2")
    if priority in ("P0", "P1"):
        raw = t.get("raw_input", "Sans description")[:100]
        error = (t.get("error") or "")[:100]
        lines.append(f"- **[{priority}]** {raw}")
        lines.append(f"  Raison: {error}")
        lines.append(f"  Action: Relancer manuellement ou re-planifier")
        lines.append("")
        actions_found = True

for t in failed_tasks:
    result = t.get("result", {})
    if isinstance(result, dict) and result.get("status") == "partial":
        raw = t.get("raw_input", "Sans description")[:80]
        lines.append(f"- **Resultat partiel:** {raw}")
        lines.append(f"  Verifier et completer manuellement")
        lines.append("")
        actions_found = True

if not actions_found:
    if fail_count > 0:
        lines.append(f"- {fail_count} echec(s) en priorite basse — pas d'action immediate requise")
    else:
        lines.append("- Aucune action requise. Tout est en ordre.")
lines.append("")

lines.append("---")
lines.append(f"*Rapport genere le {datetime.now().strftime('%Y-%m-%d a %H:%M')} par Alba Army*")

with open(report_file, "w") as f:
    f.write("\n".join(lines))

print(f"OK: {report_file}")
print(f"    {success_count} completed, {fail_count} failed, {total_tasks} total")
PYEOF

RESULT=$?
if [ $RESULT -eq 0 ]; then
    log "Report compiled: ${REPORT_FILE}"
else
    log "ERROR: report compilation failed (exit code ${RESULT})"
fi

exit $RESULT
