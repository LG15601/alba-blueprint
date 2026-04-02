---
name: calendar-ops
description: |
  Manage calendar, suggest meeting times, prepare for upcoming meetings, detect
  conflicts, and optimize scheduling. Use when asked about "calendar", "meetings",
  "disponibilites", "schedule", "agenda", or auto-triggered for daily prep.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - Glob
  - mcp__claude_ai_Google_Calendar__authenticate
  - mcp__claude_ai_Gmail__gmail_search_messages
---

# Calendar Ops -- Meeting & Schedule Management

Full calendar management: conflict detection, availability computation,
meeting preparation, and scheduling optimization.

## Arguments
- `/calendar-ops` -- today's schedule with prep notes
- `/calendar-ops week` -- this week overview
- `/calendar-ops free [day]` -- find available slots on a given day
- `/calendar-ops prep` -- prepare briefings for all upcoming meetings today
- `/calendar-ops suggest [contact] [duration]` -- suggest meeting times
- `/calendar-ops optimize` -- analyze calendar for efficiency improvements

## Step 1: Load Calendar Data

### Fetch Events
```bash
# Using gog CLI for Google Calendar
gog calendar list --from today --to "+7d" 2>/dev/null || echo "Use Calendar MCP"
```

If CLI unavailable, use Google Calendar MCP tool.

### Parse Events
For each event extract:
- Title
- Start/end time (Paris timezone)
- Location (physical or video link)
- Attendees (names, emails)
- Description/notes
- Recurring or one-time
- Organizer (us or them)

## Step 2: Today's Schedule View

### Daily Overview
```
AGENDA -- [DATE] ([DAY OF WEEK])

[TIME] - [TIME]: [Event title]
  Avec: [attendees]
  Lieu: [location or link]
  Prep: [brief note on preparation needed]
  Client-brief: [path if generated]

[TIME] - [TIME]: [Event title]
  ...

TEMPS LIBRE: [total free hours], plus grand bloc: [start]-[end]

DEMAIN:
[TIME] - [TIME]: [Event title] -- [prep needed?]
```

### Conflict Detection
Check for:
- Overlapping events
- Back-to-back meetings with no buffer (flag if external meetings have 0 gap)
- Double-booking
- Meetings during blocked focus time
- Events without video link (if remote)

If conflicts found:
```
CONFLITS DETECTES:
- [time]: [event 1] chevauche [event 2]
  Suggestion: [proposed resolution]
```

## Step 3: Availability Computation

### When Asked for Available Slots

Parameters:
- **Duration**: Meeting length (default 30 min)
- **Date range**: Which days to check
- **Business hours**: 9h-18h Paris time (default)
- **Buffer**: 15 min before/after meetings (configurable)
- **Preferences**: Morning preferred for strategy, afternoon for ops

### Slot Generation
```
1. Get all events for the date range
2. Compute occupied blocks (event start - buffer to event end + buffer)
3. Find gaps >= requested duration within business hours
4. Score each slot:
   - Morning (9h-12h): good for deep work, strategy
   - Early afternoon (14h-15h): good for focused meetings
   - Late afternoon (16h-18h): good for quick syncs
5. Exclude: lunch (12h-13h30), known blocked times
6. Return top 5 available slots, best first
```

### Output Available Slots
```
Disponibilites pour un RDV de [duration] min:

PREFERE:
- [Day] [time] - [time] (matin, ideal pour [type])
- [Day] [time] - [time]

POSSIBLE:
- [Day] [time] - [time]
- [Day] [time] - [time]
- [Day] [time] - [time]
```

## Step 4: Meeting Preparation

For each meeting today:

### Auto-Trigger /client-brief
If the meeting involves an external attendee who is a client:
```
Invoke client-brief skill with the client name
```

### General Meeting Prep
If not a client meeting:
- Research attendees (LinkedIn quick check)
- Gather context from email threads with attendees
- Note the meeting's purpose and expected outcomes
- Check if there are action items from a previous meeting with same people

### Pre-Meeting Checklist
```
PREP: [Meeting title] a [time]
- [ ] Brief prepare (ou non necessaire)
- [ ] Documents a partager prets
- [ ] Lien video verifie
- [ ] Derniers emails avec [attendee] relus
- [ ] Objectif de la reunion: [objective]
- [ ] Duree prevue: [duration]
```

## Step 5: Smart Scheduling Suggestions

### Meeting Request Handling
When Ludovic needs to schedule a meeting:

1. Compute available slots (Step 3)
2. Consider attendee timezone if international
3. Draft scheduling email:

```
Bonjour [Prenom],

Voici mes disponibilites pour notre echange:

- [Day] [time] ([timezone])
- [Day] [time] ([timezone])
- [Day] [time] ([timezone])

Si aucun creneau ne convient, n'hesitez pas a me proposer d'autres options.

Cordialement,
Ludovic
```

### Calendar Optimization (weekly)
Analyze the week for:
- Meeting density: too many meetings? (threshold: 6+ meetings/day)
- Focus time: are there blocks of 2+ hours uninterrupted?
- Meeting clustering: can meetings be grouped to free half-days?
- Recurring meetings: are they all still necessary?

```
ANALYSE AGENDA -- Semaine du [DATE]

Reunions: [N] total ([X]h)
Temps libre: [Y]h ([Z] blocs de 2h+)
Journee la plus chargee: [day] ([N] reunions)
Journee la plus libre: [day] ([N]h libres)

SUGGESTIONS:
- [suggestion: e.g., "Mardi a 6 reunions, deplacer [meeting] a jeudi?"]
- [suggestion: e.g., "Pas de bloc focus lundi, bloquer 9h-11h?"]
```

## Step 6: Post-Meeting Actions

After a meeting ends (when Ludovic provides notes or summary):
- Create follow-up tasks in dispatch queue
- Draft follow-up email if needed
- Update CRM if client meeting
- Schedule next meeting if discussed
- Log meeting outcomes

## Output Files
```bash
mkdir -p ~/.alba/calendar
# Daily schedule
echo '[schedule]' > ~/.alba/calendar/YYYY-MM-DD-schedule.json
# Available slots cache (refresh daily)
echo '[slots]' > ~/.alba/calendar/available-slots.json
# Meeting prep documents
echo '[prep]' > ~/.alba/calendar/prep/YYYY-MM-DD-[meeting-slug].md
```

## Orchestra Rules
- All times in Europe/Paris timezone
- Business hours: 9h-18h Monday-Friday
- No meetings before 9h or after 18h30 unless Ludovic explicitly agrees
- Lunch break sacred: 12h-13h30 (no meetings)
- Client meetings get priority over internal meetings
- Friday afternoon: minimize meetings (weekly retro time)
- Never auto-accept meeting invitations
- Never auto-decline without Ludovic's input
- If someone proposes a meeting: suggest Ludovic's available slots, do not accept
- Include travel time for physical meetings (check Google Maps)
- Respect French holidays (jours feries): no meetings
- Summer period (August): reduced availability, flag to contacts
