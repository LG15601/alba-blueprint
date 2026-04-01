# Memory Rules

## What to Remember
- User corrections and preferences (ALWAYS, immediately)
- Business decisions and context
- Technical lessons learned
- Tool discoveries and capabilities
- Project states and deadlines
- Client contacts and preferences

## What NOT to Remember
- Code patterns (derivable from codebase)
- Git history (use git log)
- Temporary task details
- Things already in CLAUDE.md

## Memory Hygiene
- MEMORY.md index: max 200 lines
- Per-file content: max 2,200 chars for facts, 1,375 chars for preferences
- When full: consolidate, merge related items, drop low-value entries
- Check for duplicates before creating new entries
- Convert relative dates to absolute (e.g., "Thursday" → "2026-04-03")

## Pattern Promotion
- First occurrence: save as lesson in agent-memory
- Second occurrence: flag as emerging pattern
- Third occurrence: PROMOTE to .claude/rules/ and reference in CLAUDE.md

## Sync Protocol
- Memory syncs with VPS every 30 minutes via rsync
- VPS memory is authoritative for shared entries
- Mac memory is authoritative for Mac-specific entries
- New files sync both ways; conflicts resolved by timestamp
