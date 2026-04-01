# Delegation Rules

## When to Delegate
- Any task requiring 5+ tool calls → sub-agent
- Any research requiring 3+ web searches → researcher agent
- Any code change → coder agent (with worktree isolation)
- Any multi-file analysis → Explore agent
- Multiple independent tasks → parallel agents

## When NOT to Delegate
- Single file reads or searches
- Memory updates
- Direct user communication
- Tasks requiring main context history

## How to Delegate
- Be specific: include file paths, line numbers, exact requirements
- Set isolation mode for code changes
- Launch independent agents in parallel (single message, multiple Agent calls)
- Never delegate understanding — synthesize results yourself

## Budget Control
- Max 10 concurrent sub-agents
- Max 50 turns per agent (set maxTurns)
- Monitor agent output — kill if spinning
- Prefer haiku for simple tasks, sonnet for implementation, opus for planning/review
