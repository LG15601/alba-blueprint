# Autoresearch — Team Protocol Optimization

## Mission
Test and optimize the Alba Team Protocol by running real coding tasks through
different team configurations. Measure quality, speed, and cost. Keep the best.

## What You're Optimizing
The file `TEAM-PROTOCOL.md` defines how Alba spawns and coordinates agents.
Your job: find the configuration that produces the BEST code quality with the
LEAST tokens and time.

## Test Task
Use a REAL but bounded task on the Imagin Funéraire codebase:

**Task:** "Add a lead scoring explanation tooltip that shows score breakdown
factors when hovering over a lead's score in the pipeline kanban view."

This task is ideal because it:
- Touches 2-3 files (bounded)
- Needs planning (which files? what data?)
- Needs coding (new component)
- Needs review (UX quality, accessibility)
- Has clear acceptance criteria
- Can be verified (TypeScript + visual)

## The Variables to Test

### V1: Team Size
- **Config A:** Solo agent (planner+coder+reviewer in one)
- **Config B:** Two agents (planner → coder)
- **Config C:** Three agents (planner → coder → reviewer)
- **Config D:** Four agents (planner → coder → reviewer+QA → synthesizer)

### V2: Planning Depth
- **Shallow:** One-paragraph issue description
- **Medium:** Issue with acceptance criteria + file list
- **Deep:** Full IssueGuidance (scope, risk, tests, review focus)

### V3: Context Strategy
- **Full dump:** Entire file contents in prompt
- **Targeted:** Only relevant functions/components
- **Minimal:** File paths only, agent reads what it needs

### V4: Review Style
- **None:** Ship without review
- **Checklist:** TypeScript + lint only
- **LLM review:** Another agent reviews the diff
- **Combined:** TypeScript + lint + LLM review

## Evaluation Metrics (scored 0-10)

For each configuration run:

1. **Correctness** (0-10)
   - Does the code compile? (TypeScript --noEmit)
   - Does it match acceptance criteria?
   - Are there bugs?

2. **Quality** (0-10)
   - Code style consistency
   - Accessibility
   - Performance (no unnecessary re-renders)
   - Error handling

3. **Efficiency** (0-10)
   - Number of files read (fewer = better)
   - Total prompt tokens (estimate from message sizes)
   - Number of rounds/retries
   - Wall clock time

4. **Robustness** (0-10)
   - Did it handle edge cases?
   - Would it work in production?
   - Is there tech debt?

**Composite Score = (Correctness × 3 + Quality × 2 + Efficiency × 2 + Robustness × 1) / 8**

## Experiment Loop

```
FOR each configuration combination:
  1. Create fresh git branch: test/team-{config-id}
  2. Write the team config to test/configs/{config-id}.md
  3. Simulate the workflow:
     - Generate the plan (as the planner would)
     - Write the code (as the coder would)
     - Review (as the reviewer would, if applicable)
  4. Run TypeScript check
  5. Score on all 4 metrics
  6. Record in test/results.jsonl:
     {config_id, correctness, quality, efficiency, robustness, composite, notes}
  7. Revert to clean state: git checkout main -- frontend/
  8. NEXT configuration
```

## Output
After all experiments:
1. Rank all configurations by composite score
2. Write `test/BEST-CONFIG.md` with the winning configuration
3. Write `test/RECOMMENDATIONS.md` with:
   - What team size works best
   - What planning depth matters most
   - What context strategy is optimal
   - What review style has best ROI
4. Update `TEAM-PROTOCOL.md` with findings

## Rules
- Do NOT actually spawn sub-agents — you simulate all roles yourself
- DO create real code changes for each test
- DO run real TypeScript checks
- DO revert between tests (clean state)
- Track everything in test/results.jsonl
- NEVER STOP until all meaningful combinations are tested
- Start with the most different configs (A vs D, shallow vs deep)
- Then narrow down around the best performers
