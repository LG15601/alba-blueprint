---
name: calendar-manager
description: "Daily calendar review, conflict detection, agenda summary, auto-event creation from invitations, meeting prep coordination. Use when asked about calendar, schedule, meetings, or agenda."
user-invocable: true
version: "1.0"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
---

# Calendar Manager — Daily Calendar Operations

Daily calendar review and optimization for Ludovic. Primary calendar on sales@orchestraintelligence.fr. Detects conflicts, prepares daily agenda, auto-creates events from email invitations, and triggers meeting prep.

## Primary Calendar

- **Account**: sales@orchestraintelligence.fr
- **Timezone**: Europe/Paris (CET/CEST)
- **Tool**: `gog calendar` CLI

## Step-by-step Workflow

### 1. Retrieve today's events

```bash
TODAY=$(date +%Y-%m-%d)
TOMORROW=$(date -v+1d +%Y-%m-%d)

gog calendar list --account sales@orchestraintelligence.fr \
  --start "${TODAY}T00:00:00" --end "${TODAY}T23:59:59" \
  --format json > /tmp/calendar_today.json

# Also fetch tomorrow for prep
gog calendar list --account sales@orchestraintelligence.fr \
  --start "${TOMORROW}T00:00:00" --end "${TOMORROW}T23:59:59" \
  --format json > /tmp/calendar_tomorrow.json
```

### 2. Detect conflicts

Check for overlapping events:
- Two events at the same time = CONFLICT (flag immediately)
- Less than 15 minutes between consecutive events = WARNING (suggest buffer)
- Back-to-back for 3+ hours = FATIGUE WARNING (suggest break)
- Event during protected deep work block (09:00-11:00) = OVERRIDE CHECK

```bash
# Parse events and detect overlaps
# Output: list of conflicts with suggested resolutions
```

### 3. Prepare daily agenda summary

Format:

```
## Agenda — Mercredi 1er Avril 2026

### Matin
- 09:00-10:00 — Deep Work (protected)
- 10:30-11:00 — Standup equipe
- 11:00-12:00 — Call client Wella (PREP: voir brief client)

### Apres-midi
- 14:00-15:00 — Demo produit Smart Renovation
- 15:30-16:00 — 1:1 avec Pablo
- 16:00-17:00 — Libre

### Alertes
- ⚠ Conflit: 14:00 Demo chevauche avec livraison dev prevue
- ℹ Demain: 3 meetings, dont 1 client nouveau (preparer brief)

### Temps libre identifie
- 12:00-14:00 (dejeuner + libre)
- 17:00-19:00 (fin de journee)
```

### 4. Check for unprocessed invitations

Scan inboxes for calendar invitations that weren't auto-accepted:

```bash
# Search for .ics attachments and calendar invitation emails
for account in sales@orchestraintelligence.fr ludovic@orchestraintelligence.fr; do
  gog gmail search --account "$account" \
    --query "filename:ics OR subject:(invitation OR invite OR meeting) newer_than:7d" \
    --format json
done
```

For each found invitation:
1. Check if event already exists on calendar
2. If not, extract event details (date, time, attendees, location)
3. Create event on sales@ calendar
4. Log the auto-creation

```bash
gog calendar create --account sales@orchestraintelligence.fr \
  --title "Meeting Title" \
  --start "2026-04-02T14:00:00" --end "2026-04-02T15:00:00" \
  --description "Auto-created from email invitation" \
  --attendees "attendee@example.com"
```

### 5. Trigger meeting prep for client meetings

For any event containing client names (from client-manager CRM data):
1. Identify the client
2. Check if a brief already exists for this meeting
3. If not, flag it for client-brief skill execution
4. Add prep time block 30 minutes before the meeting

```bash
# Add prep block before client meeting
gog calendar create --account sales@orchestraintelligence.fr \
  --title "PREP: Meeting [Client Name]" \
  --start "2026-04-01T10:30:00" --end "2026-04-01T11:00:00" \
  --description "Prepare brief for upcoming client meeting"
```

### 6. Weekly calendar optimization (Monday morning)

On Mondays, additionally:
- Review the full week ahead
- Identify meeting-heavy days vs. light days
- Suggest rescheduling to balance the week
- Flag any missing recurring meetings
- Check for French holidays / bridge days

## Conflict Resolution Suggestions

When conflicts are detected, propose solutions in priority order:
1. Move the less important meeting (internal < client < investor)
2. Shorten one meeting if it has padding
3. Propose alternative times from free slots
4. Decline the lower-priority meeting with polite message

## Calendar Rules

- **Buffer time**: 15 minutes between meetings minimum
- **Deep work**: 09:00-11:00 protected daily (override requires Ludovic's approval)
- **Lunch**: 12:30-13:30 soft block (can be overridden for client lunches)
- **No meetings after 18:00** unless international timezone requires it
- **Friday afternoons**: light meetings only (wind-down time)
- **Prep time**: 30 minutes before client/investor meetings auto-blocked

## Output

- Daily agenda summary in markdown (French)
- Conflict alerts with resolution suggestions
- List of auto-created events from invitations
- Meeting prep action items

## Integration

- **morning-admin skill**: calls this for daily calendar review
- **client-manager skill**: provides client names for meeting identification
- **personal-assistant agent**: receives conflict alerts and prep tasks
- **daily-briefing skill**: consumes the agenda summary
