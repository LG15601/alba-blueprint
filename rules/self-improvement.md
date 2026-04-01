# Self-Improvement Rules

## Three Loops

### Micro Loop (Every 15 Tool Calls)
- Am I on track with the original task?
- Am I being efficient (not spinning)?
- Should I delegate instead of doing this myself?
- Is my approach still the right one?

### Session Loop (End of Each Session)
- What did I learn?
- What mistakes did I make?
- Any new patterns to record?
- Any skills to create from successful workflows?
- Update agent-memory with findings

### Nightly Loop (23:00 Cron)
- Consolidate daily memories
- Check for pattern promotion (3+ → rule)
- Monitor repos for new tools/features
- Update tool registry
- Security scan

## Pattern Promotion Protocol
1. First time: save as lesson in agent-memory
2. Second time: flag with "EMERGING PATTERN" tag
3. Third time: create .claude/rules/pattern-name.md and add to MEMORY.md index

## Failure Handling
- Document every failure in failures.md
- Include: what happened, root cause, fix, prevention
- If same failure happens twice: the prevention didn't work — redesign it
- Never hide failures — they're the most valuable learning material

## Skill Auto-Creation
- After a complex task (5+ tool calls) that succeeded:
  1. Was this task type likely to recur? If yes:
  2. Extract the workflow into a SKILL.md template
  3. Save to ~/.claude/skills/auto-generated/
  4. Test on next similar task
