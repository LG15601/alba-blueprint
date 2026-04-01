# Alba Team Protocol v1.0

> Inspired by SWE-AF (roles & escalation) + GSD 2.0 (methodology & verification)
> Adapted for Middleman swarm on Mac Mini M4

---

## Core Principle

**Every task follows the same cycle. No exceptions.**

```
DISCUSS → PLAN → EXECUTE → VERIFY → SHIP
```

---

## 1. Roles

### 🎯 Alba (Manager)
- **Never codes.** Never executes. Commands only.
- Routes work to the right role
- Monitors progress, unblocks, escalates to Ludo
- Maintains team protocol and memory
- Decides DPYS: Dispatch / Prep / Yours / Skip

### 📋 Planner
- Reads the goal + codebase
- Produces: PRD with acceptance criteria, architecture, issue DAG
- Each issue gets an `IssueGuidance`:
  ```yaml
  scope: trivial | small | medium | large
  needs_tests: bool
  needs_deep_qa: bool
  files_to_create: [...]
  files_to_modify: [...]
  depends_on: [issue-ids]
  review_focus: "what reviewer should check"
  risk: "why this is/isn't risky"
  ```
- Output: `.planning/issues/issue-{NN}-{slug}.md`

### 🏗 Coder
- Reads ONE issue spec → writes code
- Follows the issue guidance exactly
- Runs TypeScript/lint/test after each change
- Commits with descriptive messages
- Works on isolated git branch: `issue/{NN}-{slug}`
- **NEVER decides scope or priority** — that's the Planner's job

### 🔍 Reviewer
- Reads the diff produced by Coder
- Checks against acceptance criteria from issue spec
- Checks: correctness, security, performance, style
- Verdict: APPROVE / REQUEST_CHANGES / BLOCK
- If REQUEST_CHANGES → specific actionable feedback → back to Coder
- Max 3 review rounds per issue, then escalate

### 🧪 QA (for flagged issues only)
- Runs in parallel with Reviewer
- Focuses on: edge cases, error handling, integration risks
- Runs actual tests, tries to break things
- Verdict: PASS / FAIL with reproduction steps

### 🔀 Synthesizer (for flagged issues only)
- Merges Reviewer + QA feedback into single verdict
- Detects stuck loops (coder cycling without progress)
- Can break the loop early if no progress after 2 rounds

### 🚨 Advisor (activated on failure)
- Activated when inner loop exhausts without approval
- 5 possible actions:
  1. **RETRY_MODIFIED** — relax criteria, retry (dropped criteria = tech debt)
  2. **RETRY_APPROACH** — same criteria, different strategy
  3. **SPLIT** — break issue into sub-issues
  4. **ACCEPT_WITH_DEBT** — close enough, record gaps
  5. **ESCALATE** — can't fix locally, escalate to Alba/Ludo

---

## 2. Workflow

### Phase 0: DISCUSS (when goal is ambiguous)
```
Alba → Planner: "Analyze this goal, identify gray areas"
Planner → Alba: structured questions
Alba → Ludo: ask via escalation
Ludo → Alba: answers
Alba → Planner: "Here are the answers, proceed to plan"
Output: context.md with all decisions
```

### Phase 1: PLAN
```
Alba → spawn Planner with goal + repo path
Planner:
  1. Read codebase (key files, structure, existing patterns)
  2. Write PRD: requirements, acceptance criteria, out-of-scope
  3. Write architecture: components, interfaces, decisions
  4. Decompose into issues with DAG (dependency graph)
  5. Write issue specs with IssueGuidance
  6. Topological sort → parallel execution levels
Output: .planning/prd.md, .planning/arch.md, .planning/issues/*.md
```

### Phase 2: EXECUTE (per dependency level)
```
For each level in DAG:
  For each issue in level (parallel):
    
    IF issue.needs_deep_qa == false:
      # Fast path (2 agents)
      Coder → writes code on branch
      Reviewer → checks diff
      IF APPROVE → merge to integration branch
      IF REQUEST_CHANGES → Coder fixes (max 3 rounds)
      IF BLOCK → Advisor activated

    IF issue.needs_deep_qa == true:
      # Deep path (4 agents)
      Coder → writes code on branch
      Reviewer + QA → check in parallel
      Synthesizer → merge feedback
      IF APPROVE → merge to integration branch
      IF REQUEST_CHANGES → Coder fixes (max 3 rounds)
      IF BLOCK → Advisor activated
  
  # Level barrier (all issues in level must complete)
  Merge all branches → integration branch
  Run integration tests
  Checkpoint DAGState
```

### Phase 3: VERIFY
```
4-tier verification ladder (from GSD 2.0):

Tier 1 — STATIC
  - Files exist, exports present, no stubs
  - TypeScript compiles: tsc --noEmit
  - ESLint clean

Tier 2 — COMMAND  
  - Tests pass: pnpm test
  - Build succeeds: pnpm build
  - No regressions

Tier 3 — BEHAVIORAL
  - Lighthouse audit (if web)
  - Screenshot comparison
  - API response validation
  - Key user flows work

Tier 4 — HUMAN (only when agent can't verify)
  - UAT generated: human-readable test steps
  - Escalation to Ludo with specific questions
```

### Phase 4: SHIP
```
  - Squash merge integration → main
  - One clean commit per feature
  - Deploy (if applicable)
  - Update memory with what was done
```

---

## 3. Escalation Protocol

```
Level 1 (Inner): Coder retries (max 5x)
Level 2 (Middle): Advisor changes approach (max 2x)
Level 3 (Outer): Alba replans the DAG
Level 4 (Human): Escalate to Ludo

NEVER:
  - Retry the same thing >5 times
  - Silently accept broken code
  - Skip verification
  - Block forever — always have a timeout
```

---

## 4. Context Management (from GSD 2.0)

### Per-task context injection
Each Coder receives ONLY:
- The issue spec (acceptance criteria, guidance)
- Relevant file contents (from files_to_modify/create)
- Dependency summaries (from completed issues)
- Key decisions from context.md

### NO:
- Full repo dump
- Other issues' specs
- Previous conversation history
- Unrelated code

### Fractal summaries
- Task completes → 3-line summary
- Level completes → level summary
- Feature completes → feature summary
- Summaries flow DOWN to dependent tasks

---

## 5. Git Strategy (from GSD 2.0)

```
main ← squash merge per feature
  └── integration/{feature} ← merge gate per level
        ├── issue/01-setup-schema
        ├── issue/02-api-routes
        └── issue/03-frontend-components
```

- Branch per issue (isolated)
- Merge to integration at level barrier
- Squash to main on ship
- Checkpoint after each level

---

## 6. Agent Spawn Templates

### Planner spawn
```
Role: PLANNER
Goal: {goal}
Repo: {repo_path}
Skills: [gsd, project-manager]
Output: .planning/prd.md, .planning/arch.md, .planning/issues/*.md
Rules:
  - Read codebase BEFORE planning
  - Each issue ≤ 1 context window of work
  - Include IssueGuidance in every issue
  - Topological sort for parallel execution
```

### Coder spawn  
```
Role: CODER
Issue: .planning/issues/issue-{NN}.md
Branch: issue/{NN}-{slug}
Skills: [{relevant-skills}]
Rules:
  - Read the issue spec FIRST
  - Work ONLY on files listed in the spec
  - Run TypeScript check after each change
  - Commit with descriptive messages
  - DO NOT modify files outside your scope
```

### Reviewer spawn
```
Role: REVIEWER
Branch: issue/{NN}-{slug}
Criteria: {acceptance_criteria from issue spec}
Focus: {review_focus from IssueGuidance}
Rules:
  - Review diff against acceptance criteria
  - Check security, performance, patterns
  - Be specific: line numbers + suggested fixes
  - Verdict: APPROVE / REQUEST_CHANGES / BLOCK
  - Max 3 rounds then escalate
```

---

## 7. Metrics (for autoresearch optimization)

### Efficiency
- Issues completed / total issues
- Average rounds per issue (lower = better)
- Escalation rate (lower = better)
- Total tokens consumed / feature delivered

### Quality
- TypeScript errors after completion (target: 0)
- Lighthouse score delta
- Test coverage delta
- Tech debt items created

### Speed
- Time from goal → shipped
- Parallel utilization (issues running simultaneously)
- Blocked time (waiting on dependencies)

---

## 8. Anti-patterns (NEVER DO)

❌ One giant prompt with everything  
❌ Coder decides its own scope  
❌ Skip planning, go straight to code  
❌ No review, just ship  
❌ Silent failure → Alba does it manually  
❌ Full repo context in every agent  
❌ Infinite retry loops  
❌ Agent modifies files outside its issue scope  
