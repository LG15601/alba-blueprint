---
name: self-improve
description: "End-of-session self-improvement protocol. Consolidate learnings, update memories, detect patterns, create skills from successful workflows."
disable-model-invocation: true
user-invocable: false
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Self-Improvement Protocol

Run at end of every session (triggered by Stop hook).

## Step 1: Session Review
- What tasks were completed this session?
- What worked well? What was efficient?
- What failed or was slow? Why?
- Any corrections from the user?

## Step 2: Learning Extraction
For each lesson learned:
1. Check if it already exists in agent-memory
2. If new: add to ~/.claude/agent-memory/alba/MEMORY.md
3. If existing: increment occurrence count
4. If occurrence >= 3: PROMOTE to ~/.claude/rules/

## Step 3: Failure Registry
For each failure:
1. Document in ~/.claude/agent-memory/alba/failures.md
2. Include: what happened, root cause, fix, prevention
3. Check if same failure happened before — if so, the prevention didn't work

## Step 4: Skill Detection
If a complex task (5+ tool calls) succeeded:
1. Was this task type likely to recur?
2. If yes: extract workflow into skill template
3. Save to ~/.claude/skills/auto-generated/SKILL_NAME/SKILL.md
4. Log in ~/.claude/agent-memory/alba/skills-created.md

## Step 5: Tool Discovery
- Were any new tools used or discovered this session?
- If yes: update ~/.alba/tool-registry.json

## Step 6: Memory Hygiene
- Is MEMORY.md under 200 lines? If not, consolidate
- Are there stale entries (>30 days, never referenced)? Mark for review
- Any duplicate entries? Merge them

## Rules
- Be honest about failures — sugar-coating prevents learning
- Only save genuinely useful lessons — no noise
- Keep entries concise (2-3 lines max per lesson)
- This runs silently — don't output to user unless critical
