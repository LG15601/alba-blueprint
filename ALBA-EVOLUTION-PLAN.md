# ALBA EVOLUTION PLAN — From 42/100 to 75/100

> **Generated**: 2026-04-01 | **Target**: 8 weeks | **Method**: GSD milestone/slice/task hierarchy
> **Sources**: 7 parallel research agents analyzed 14 open-source projects (OpenClaw 344K★, Hermes 21K★, GStack 59K★, Paperclip 30K★, Agency Agents 68K★, Autoresearch 63K★, Claude-Mem 44K★, Claw Code 50K★)

## Current State: 42/100

| Category | Score | Target |
|----------|-------|--------|
| Infrastructure | 34 | 62 |
| Memory & Intelligence | 33 | 72 |
| Multi-Agent Orchestration | 24 | 65 |
| Self-Improvement | 7 | 60 |
| Integrations | 26 | 50 |
| Security | 38 | 65 |
| Code Quality & Testing | 16 | 55 |
| Autonomy & UX | 18 | 55 |
| Business-Specific | 78 | 85 |
| **TOTAL** | **42** | **75** |

---

## M1 — MEMORY & INTELLIGENCE ENGINE
> **Impact**: 33 → 72 (+39 pts) | **Priority**: 🔴 CRITICAL | **Duration**: ~2 weeks
> **Stolen from**: Hermes (3-layer memory), Claude-Mem (FTS5 + progressive disclosure), KAIROS (autoDream)

### S01 — SQLite FTS5 Session Store
Build a searchable cross-session memory using SQLite with full-text search, modeled on Hermes Agent's `hermes_state.py` and Claude-Mem's observation system.

**Tasks:**

- **T01 — Create SQLite schema and migration system**
  - Database: `~/.alba/alba-memory.db` with WAL mode
  - Tables: `sessions` (id, project, started_at, ended_at, message_count, tool_call_count, title, summary)
  - Tables: `observations` (id, session_id, type [decision|bugfix|feature|refactor|discovery|change], title, subtitle, narrative, facts JSON, concepts JSON, files_read JSON, files_modified JSON, tokens_cost, created_at)
  - Tables: `session_summaries` (id, session_id, request, investigated, learned, completed, next_steps)
  - FTS5 virtual tables: `observations_fts` (title, subtitle, narrative, facts, concepts) with INSERT/DELETE/UPDATE triggers for auto-sync
  - Pragma optimizations: `journal_mode=WAL`, `synchronous=NORMAL`, `mmap_size=268435456`, `cache_size=10000`
  - Migration system: numbered SQL files in `~/.alba/migrations/`, version tracked in `meta` table
  - **Source**: Hermes `hermes_state.py` schema v6 + Claude-Mem `Database.ts`

- **T02 — Build observation capture hook**
  - PostToolUse hook in `settings.json` that fires after every tool call
  - Hook script (`~/.alba/hooks/capture-observation.sh`) receives tool_name, tool_input, tool_output via stdin
  - Batches tool calls (buffer 3-5 calls before processing) to reduce overhead
  - Extracts structured observations using a secondary cheap model call (Haiku) with XML format:
    ```xml
    <observation>
      <type>discovery</type>
      <title>Short title</title>
      <facts><fact>Detail 1</fact></facts>
      <concepts><concept>tag1</concept></concepts>
    </observation>
    ```
  - Writes to SQLite via `sqlite3` CLI (no dependencies)
  - "Never discard" policy: always save, even if extraction is partial
  - **Source**: Claude-Mem `worker-service.cjs` hook chain

- **T03 — Build session summary capture**
  - SessionEnd hook that generates a structured summary of the entire session
  - Reads recent observations for the session, produces: request, investigated, learned, completed, next_steps
  - Writes to `session_summaries` table
  - **Source**: Claude-Mem session summary format

- **T04 — Build search MCP tool**
  - Python or Node script exposed as MCP tool: `alba-memory-search`
  - Supports: `search(query, limit, type, date_range)` → returns compact index (ID, time, type, title, ~tokens)
  - Supports: `get_observations(ids)` → returns full observation details
  - Supports: `timeline(anchor_id, depth_before, depth_after)` → chronological context window
  - Progressive disclosure: search returns titles only (~50 tokens each), get_observations returns full content (~500-1000 tokens each)
  - **Source**: Claude-Mem MCP tools API

### S02 — Progressive Disclosure Context Injection
Inject compact memory timeline into every session start, following Claude-Mem's 3-layer architecture.

**Tasks:**

- **T01 — Build SessionStart context injector**
  - Hook script that queries SQLite on session start
  - Injects into system prompt via `$CONTEXT` environment variable or temporary file
  - Configuration: `totalObservationCount` (default 30), `fullObservationCount` (default 5), `sessionCount` (default 3)
  - Most observations render as table row: `| ID | Time | Type | Title | ~ReadTokens |`
  - Only N most recent get full narrative + facts
  - Token budget: max 4,000 tokens for context injection
  - **Source**: Claude-Mem progressive disclosure, KAIROS 3-layer memory

- **T02 — Build frozen snapshot pattern**
  - MEMORY.md and session context loaded at session start as frozen snapshot
  - Mid-session writes update disk but do NOT change the active prompt (preserves prompt cache)
  - Snapshot refreshes on next session only
  - **Source**: Hermes Agent frozen snapshot pattern

### S03 — autoDream Nightly Consolidation
Automated memory consolidation running nightly, inspired by KAIROS daemon's autoDream.

**Tasks:**

- **T01 — Build nightly consolidation cron job**
  - Three-gate trigger: (1) 24h since last consolidation, (2) minimum 5 sessions since last, (3) lock acquired
  - Four phases:
    1. **Orient**: Read MEMORY.md + all topic files
    2. **Gather**: Query recent observations, find drifted/contradictory memories
    3. **Consolidate**: Update/merge memory files, convert relative → absolute dates, delete contradictions
    4. **Prune**: Keep MEMORY.md under 200 lines, remove stale entries (>90 days with low access)
  - Runs as sub-agent with read-only access to project files
  - Logs consolidation actions to `~/.alba/logs/consolidation.log`
  - **Source**: KAIROS autoDream 4-phase pattern

- **T02 — Memory injection scanning hardening**
  - Upgrade `memory_guard.py` from 33 patterns to 98 patterns (port from Hermes `skills_guard.py`)
  - Add categories: obfuscation (14 patterns), supply chain (8), persistence (10), network (10), credential exposure (6)
  - Add invisible Unicode detection for 17 specific codepoints
  - Apply scanning to ALL memory writes (MEMORY.md, topic files, observations)
  - **Source**: Hermes `skills_guard.py` 98 patterns across 13 categories

---

## M2 — MULTI-AGENT ORCHESTRATION
> **Impact**: 24 → 65 (+41 pts) | **Priority**: 🔴 CRITICAL | **Duration**: ~2 weeks
> **Stolen from**: Hermes (delegation constraints), OpenClaw (command lanes), Middleman (manager-worker), Agency Agents (handoffs + quality gates)

### S01 — Delegation Engine with Hard Limits
Replace soft CLAUDE.md delegation guidelines with enforced constraints.

**Tasks:**

- **T01 — Build delegation enforcement hook**
  - PreToolUse hook that intercepts Agent tool calls
  - Enforces hard limits:
    - `MAX_CONCURRENT_CHILDREN = 3`
    - `MAX_DEPTH = 2` (parent → child → grandchild rejected)
    - `DEFAULT_MAX_ITERATIONS = 50`
  - Tracks active children in `/tmp/alba-agent-children.json`
  - Blocks if limits exceeded (exit code 2)
  - **Source**: Hermes `delegate_tool.py` hard limits

- **T02 — Implement blocked tools for sub-agents**
  - Sub-agents CANNOT use:
    - `delegate_task` (no recursive delegation beyond depth 2)
    - Memory write tools (no shared MEMORY.md mutations)
    - Telegram/Slack reply tools (no user-facing side effects)
    - `execute_code` (children should reason, not script)
  - Enforcement: inject blocked tool list into sub-agent system prompt + PreToolUse hook check
  - **Source**: Hermes `DELEGATE_BLOCKED_TOOLS` frozenset

- **T03 — Toolset intersection enforcement**
  - Children can ONLY have tools the parent has
  - When spawning sub-agent, compute: `child_tools = parent_tools ∩ requested_tools - blocked_tools`
  - Log tool restriction decisions to `~/.alba/logs/delegation.log`
  - **Source**: Hermes toolset intersection pattern

### S02 — Command Lane Queue System
Implement OpenClaw's 4-lane concurrency model to prevent resource contention.

**Tasks:**

- **T01 — Build command lane manager**
  - 4 lanes: `main` (concurrency 1), `cron` (concurrency 1), `subagent` (concurrency 3), `nested` (concurrency 1)
  - File-based queue: `~/.alba/lanes/{lane}.queue.json`
  - Each lane is a semaphore: `{queue: Entry[], active: Set<id>, maxConcurrent: number}`
  - `pump()` function dequeues when slots open
  - Graceful draining support for shutdown
  - **Source**: OpenClaw `command-queue.ts` + `lanes.ts`

- **T02 — Integrate lanes with watchdog**
  - Watchdog health check includes lane status
  - Detect stuck lanes (task active > 10 min without progress)
  - Kill stuck tasks and free lane slots
  - Report lane utilization in `status` command output

### S03 — Structured Handoff Protocol
Replace freeform agent messaging with structured handoff documents.

**Tasks:**

- **T01 — Define 5 handoff templates**
  - Templates as markdown in `~/.alba/templates/handoffs/`:
    1. **Standard**: from_agent, to_agent, context, deliverable_request, acceptance_criteria
    2. **QA Pass**: task_id, evidence (screenshots/logs), verification_checklist
    3. **QA Fail**: issue_list (severity, expected, actual), fix_instructions, retry_count (attempt N of 3)
    4. **Escalation**: failure_history, root_cause_analysis, recommended_resolution, impact_assessment
    5. **Completion**: summary, artifacts_produced, learnings, next_steps
  - **Source**: Agency Agents 7 handoff templates

- **T02 — Dev-QA loop with retry limits**
  - Pattern: Build → Test → PASS/FAIL
  - Max 3 attempts before escalation
  - On 3rd failure: generate Escalation handoff with root cause analysis
  - Escalation options: reassign, decompose, revise approach, accept risk, defer
  - **Source**: Agency Agents Phase 3 Dev-QA loop

- **T03 — Completion report auto-routing**
  - When sub-agent finishes (via Agent tool return), automatically:
    1. Parse result into Completion handoff template
    2. Extract learnings and write to operational learning log
    3. Notify parent agent with structured summary
  - No polling needed — event-driven on Agent tool completion
  - **Source**: Middleman completion report pattern

---

## M3 — SELF-IMPROVEMENT ENGINE
> **Impact**: 7 → 60 (+53 pts) | **Priority**: 🟡 HIGH | **Duration**: ~1.5 weeks
> **Stolen from**: Hermes (skill auto-creation), GStack (operational learning), KAIROS (autoDream), Autoresearch (never-stop philosophy)

### S01 — Operational Learning System
Implement GStack's append-only learning journal.

**Tasks:**

- **T01 — Create learnings.jsonl system**
  - File: `~/.alba/learnings.jsonl` (append-only)
  - Schema per entry:
    ```json
    {
      "ts": "2026-04-01T19:30:00Z",
      "skill": "review",
      "type": "pitfall|pattern|preference|architecture|tool|operational",
      "key": "unique-slug",
      "insight": "What was learned",
      "confidence": 8,
      "source": "observed|user-stated|inferred",
      "files": ["relevant/files.sh"],
      "occurrence_count": 1
    }
    ```
  - Read dedup: latest-winner per key+type pair
  - Confidence decay: -1pt per 30 days for observed/inferred entries
  - **Source**: GStack `learnings.jsonl` exact schema

- **T02 — Build learning capture hooks**
  - PostToolUse hook increments occurrence counter for known patterns
  - On user correction (detected via keywords: "non", "pas ça", "arrête", "stop"): auto-capture as `user-stated` learning with confidence 10
  - On task success (5+ tool calls): prompt "Was this task type likely to recur?" — if yes, capture workflow
  - **Source**: GStack learning capture + Hermes skill_manage trigger

- **T03 — Learning injection into sessions**
  - SessionStart hook loads top 5 learnings (by confidence × recency) into context
  - When a review finding matches a past learning, display: "Prior learning applied: [key] (confidence N/10)"
  - Cross-project discovery opt-in via `--global-learnings` flag
  - **Source**: GStack preamble learning injection

### S02 — Pattern Promotion Pipeline
Automate the 1st→2nd→3rd occurrence rule promotion.

**Tasks:**

- **T01 — Build occurrence tracking**
  - SQLite table `pattern_occurrences` (pattern_key, count, first_seen, last_seen, promoted_at)
  - PostToolUse hook + session-end hook scan for recurring patterns
  - Patterns identified by: same error type, same fix approach, same user correction topic
  - **Source**: Original alba-blueprint design + OpenClaw insight (they DON'T have this — we build it first)

- **T02 — Implement promotion thresholds**
  - Count 1: Save as lesson in `learnings.jsonl`
  - Count 2: Flag with `EMERGING_PATTERN` tag, increase confidence to 9
  - Count 3: Auto-create `.claude/rules/{pattern-slug}.md` with:
    - Rule statement
    - Why (from accumulated evidence)
    - How to apply (from successful resolutions)
  - Update CLAUDE.md to reference new rule
  - Log promotion to `~/.alba/logs/promotions.log`

- **T03 — Build failure documentation system**
  - File: `~/.alba/failures.jsonl`
  - On error/crash/user correction, capture:
    ```json
    {
      "ts": "...",
      "what_happened": "description",
      "root_cause": "analysis",
      "fix_applied": "what was done",
      "prevention": "how to avoid next time",
      "recurrence_count": 1
    }
    ```
  - If same failure happens twice: flag prevention as ineffective, redesign
  - **Source**: alba-blueprint self-improvement rules (now actually implemented)

### S03 — Skill Auto-Creation
After successful complex tasks, extract reusable workflows into skills.

**Tasks:**

- **T01 — Build skill extraction engine**
  - Trigger: session-end hook, if session had 5+ tool calls and succeeded
  - Prompt (via Haiku): "Was this task type likely to recur? If yes, extract a SKILL.md"
  - Generated skill goes to `~/.claude/skills/auto-generated/{slug}/SKILL.md`
  - YAML frontmatter: name, description, version, allowed-tools
  - Body: step-by-step workflow extracted from session transcript
  - **Source**: Hermes `skill_manager_tool.py` (create, edit, patch, delete)

- **T02 — Skill security scanning**
  - Every auto-generated skill passes through security scan before activation
  - Reuse memory_guard 98-pattern scanner on SKILL.md content
  - Trust policy: `agent-created` → safe=allow, caution=allow, dangerous=ask
  - Max content: 100,000 chars per SKILL.md
  - Names must match: `^[a-z0-9][a-z0-9._-]*$`
  - **Source**: Hermes `skills_guard.py` trust policy

---

## M4 — TESTING & CI PIPELINE
> **Impact**: 16 → 55 (+39 pts) | **Priority**: 🟡 HIGH | **Duration**: ~1 week
> **Stolen from**: GSD (4-tier verification), GStack (3-tier validation)

### S01 — Core Test Suites
Build TAP-format test suites for all critical Alba components.

**Tasks:**

- **T01 — Watchdog test suite (20 tests)**
  - Test health check logic (all 6 states)
  - Test circuit breaker (10 restarts/hour limit)
  - Test keepalive nudge (idle detection, false-trigger prevention)
  - Test RAM threshold detection
  - Test OAuth expiration detection
  - Test log rotation

- **T02 — Memory system test suite (15 tests)**
  - Test memory_guard patterns (injection, exfiltration, unicode)
  - Test MEMORY.md size limits (200 lines)
  - Test observation capture and FTS5 search
  - Test progressive disclosure token budgets
  - Test consolidation (merge, prune, dedup)

- **T03 — Email classifier test suite (15 tests)**
  - Test all 13 DPYS rules
  - Test VIP override logic
  - Test sentiment detection
  - Test edge cases (false positives, multi-rule conflicts)

- **T04 — Delegation test suite (10 tests)**
  - Test concurrent child limit (max 3)
  - Test depth limit (max 2)
  - Test blocked tools enforcement
  - Test toolset intersection
  - Test completion report generation

### S02 — CI Pipeline
Automate testing on every commit.

**Tasks:**

- **T01 — GitHub Actions workflow**
  - Trigger: push to main, PR creation
  - Steps: shellcheck all .sh files, run all TAP test suites, validate CLAUDE.md syntax, check for secrets in diff
  - Badge in README showing test status
  - **Source**: GStack 3-tier validation (static → E2E → LLM-judge)

- **T02 — Verification gate for watchdog**
  - Pre-restart verification: run critical tests before deploying new watchdog version
  - Auto-rollback if tests fail
  - **Source**: GSD auto-verification gate

---

## M5 — SECURITY HARDENING
> **Impact**: 38 → 65 (+27 pts) | **Priority**: 🟡 HIGH | **Duration**: ~1 week
> **Stolen from**: Hermes (skills_guard 98 patterns), Claude Code (BashTool 23 checks)

### S01 — Skills Guard Full Port
Port Hermes Agent's complete security scanning system.

**Tasks:**

- **T01 — Port 98 threat patterns**
  - 13 categories: exfiltration (18), injection (18), destructive (8), persistence (10), network (10), obfuscation (14), supply chain (8), privilege escalation (5), path traversal (5), credential exposure (6), crypto mining (2)
  - Implement as Python script: `~/.alba/security/skills_guard.py`
  - Apply to: skill installs, memory writes, hook scripts, MCP tool outputs
  - **Source**: Hermes `skills_guard.py` complete pattern set

- **T02 — Trust policy system**
  - 4 trust levels × 3 severity levels:
    ```
                    safe      caution    dangerous
    builtin:       allow     allow      allow
    trusted:       allow     allow      block
    community:     allow     block      block
    agent-created: allow     allow      ask
    ```
  - Structural limits: max 50 files per skill, max 1MB total, max 256KB per file
  - Block suspicious binary extensions (.exe, .dll, .so, .dylib)
  - **Source**: Hermes trust policy matrix

### S02 — Destructive Command Enforcement
Move from documentation to actual enforcement.

**Tasks:**

- **T01 — PreToolUse hook for Bash commands**
  - Intercept Bash tool calls before execution
  - Pattern-match against destructive commands:
    - `rm -rf /` or `rm -rf ~`
    - `git push --force` to main/master
    - `git reset --hard`
    - `DROP TABLE`, `DELETE FROM` without WHERE
    - `chmod 777`, `mkfs`, `dd if=`
  - Exit code 2 (block) with explanation message
  - User can override with explicit confirmation
  - **Source**: Claude Code BashTool 23 security checks + Hermes destructive patterns

---

## M6 — INFRASTRUCTURE & OBSERVABILITY
> **Impact**: 34 → 62 (+28 pts) | **Priority**: 🟢 MEDIUM | **Duration**: ~1 week
> **Stolen from**: OpenClaw (command lanes), Claude Code (compaction strategies), Paperclip (heartbeat + budget)

### S01 — Centralized Logging
Replace scattered logs with unified SQLite logging.

**Tasks:**

- **T01 — Build centralized log store**
  - Database: `~/.alba/alba-logs.db`
  - Tables: `events` (ts, source [watchdog|hook|cron|agent|mcp], level [debug|info|warn|error|fatal], message, metadata JSON)
  - Retention: 30 days rolling, vacuum weekly
  - Query CLI: `alba-logs search <query>` with date range and source filters
  - Replace all /tmp log files with SQLite writes

- **T02 — Build metrics collection**
  - Track per session: tool_calls, tokens_used, duration, restarts, errors
  - Track per day: total_sessions, total_tokens, total_cost_estimate, uptime_percent
  - SQLite table: `metrics` (ts, metric_name, metric_value, labels JSON)
  - Weekly trend summary in nightly consolidation

### S02 — Proactive Monitoring
Add predictive alerting instead of reactive-only.

**Tasks:**

- **T01 — Alert threshold escalation**
  - 4 restarts in 2 hours → warning alert
  - 7 restarts in 2 hours → critical alert (approaching circuit breaker)
  - OAuth token age > 6 hours → proactive refresh reminder
  - Disk usage > 85% → cleanup warning
  - MCP server not responding to 3 consecutive tool calls → MCP health alert

- **T02 — Status dashboard endpoint**
  - Simple HTTP server on localhost:18790 (behind Tailscale)
  - JSON API: `/status` (health state, uptime, active lanes, recent errors)
  - `/metrics` (daily/weekly aggregates)
  - Accessible from iPhone via Tailscale + Shortcuts

### S03 — Context Compaction Strategies
Implement Claude Code's 5-strategy compaction system.

**Tasks:**

- **T01 — Add micro-compact and context-collapse**
  - Current: only full compact (summarize everything)
  - Add micro-compact: clear tool results older than 10 turns (they're captured in observations anyway)
  - Add context-collapse: summarize conversation spans (e.g., "turns 5-15: researched X, found Y")
  - Add context pressure monitor: at 70% context usage, nudge to wrap up durable output
  - **Source**: Claude Code 5 compaction strategies

---

## M7 — AUTONOMY & PROACTIVE BEHAVIOR
> **Impact**: 18 → 55 (+37 pts) | **Priority**: 🟢 MEDIUM | **Duration**: ~1 week
> **Stolen from**: Paperclip (heartbeat + HEARTBEAT.md), Autoresearch (never-stop), KAIROS (tick pattern)

### S01 — Proactive Heartbeat System
Upgrade from reactive health checks to proactive self-triage.

**Tasks:**

- **T01 — Build HEARTBEAT.md checklist**
  - Per-session checklist that Alba evaluates every 30 minutes:
    ```markdown
    ## Alba Heartbeat Checklist
    - [ ] Any unread Telegram messages?
    - [ ] Any pending email classifications?
    - [ ] Any scheduled tasks overdue?
    - [ ] Any standing orders due?
    - [ ] Any MCP servers unhealthy?
    - [ ] Memory approaching limits?
    - [ ] Any learnings to capture from recent work?
    ```
  - If any item triggers → take action autonomously
  - If no items trigger → skip (no LLM cost)
  - **Source**: Paperclip HEARTBEAT.md proactive pattern + RFC #206

- **T02 — Standing orders execution engine**
  - Read `~/.alba/standing-orders.md` at boot
  - Parse scheduled orders with cron expressions
  - Execute via CronCreate or internal scheduler
  - Track execution history in SQLite
  - Report missed executions at next heartbeat

### S02 — Goal Hierarchy
Implement lightweight goal tracking inspired by Paperclip.

**Tasks:**

- **T01 — Build goal registry**
  - File: `~/.alba/goals.md` with hierarchy:
    ```markdown
    ## Mission
    - Run Orchestra Intelligence operations autonomously
    
    ## Active Goals
    - [ ] G01: Maintain 99% uptime (ongoing)
    - [ ] G02: Process all emails within 2h (ongoing)
    - [ ] G03: Complete alba-evolution M1-M7 (target: 2026-05-27)
    
    ## Task Backlog
    - [ ] T01 (G03/M1): Build SQLite FTS5 session store
    ```
  - Every task traces back to a goal → mission
  - Heartbeat checks goal progress and reports blockers
  - **Source**: Paperclip 4-level goal hierarchy (company → team → agent → task)

---

## EXECUTION STRATEGY

### Phase 1: Foundations (Weeks 1-2)
- **M1** (Memory) + **M4-S01** (Core tests)
- Rationale: Memory is the foundation everything else builds on. Tests prevent regressions.

### Phase 2: Orchestration (Weeks 3-4)
- **M2** (Multi-Agent) + **M5** (Security)
- Rationale: Delegation needs security guardrails. Ship together.

### Phase 3: Intelligence (Weeks 5-6)
- **M3** (Self-Improvement) + **M4-S02** (CI)
- Rationale: Self-improvement generates learnings that need CI to validate.

### Phase 4: Polish (Weeks 7-8)
- **M6** (Infrastructure) + **M7** (Autonomy)
- Rationale: Observability and proactive behavior are the final layer.

### Complexity Routing (from GSD)
| Tier | Tasks | Model |
|------|-------|-------|
| Light | Config files, templates, simple scripts | Haiku |
| Standard | Hook scripts, test suites, integrations | Sonnet |
| Heavy | SQLite schema, security scanner, delegation engine | Opus |

### Verification Ladder (from GSD)
1. **Static**: shellcheck, syntax validation, pattern matching
2. **Unit**: TAP test suites (60+ tests total)
3. **Integration**: End-to-end watchdog + delegation + memory flow
4. **UAT**: "Can Alba self-improve across sessions?" (human verification)

---

## PATTERN ATTRIBUTION

| Pattern | Source Project | Where Used |
|---------|--------------|------------|
| FTS5 session search | Hermes + Claude-Mem | M1/S01 |
| Progressive disclosure | Claude-Mem | M1/S02 |
| autoDream consolidation | KAIROS (Claude Code) | M1/S03 |
| 98 threat patterns | Hermes skills_guard | M1/S03-T02, M5/S01 |
| Delegation hard limits | Hermes delegate_tool | M2/S01 |
| Command lanes | OpenClaw command-queue | M2/S02 |
| Structured handoffs | Agency Agents | M2/S03 |
| Dev-QA retry loop | Agency Agents | M2/S03-T02 |
| Manager-worker memory | Middleman | M2/S03-T03 |
| learnings.jsonl | GStack | M3/S01 |
| Pattern promotion | Original (not in any project) | M3/S02 |
| Skill auto-creation | Hermes skill_manager | M3/S03 |
| 4-tier verification | GSD 2 | M4/S02 |
| 3-tier validation | GStack | M4/S01 |
| Trust policy matrix | Hermes | M5/S01-T02 |
| BashTool 23 checks | Claude Code | M5/S02 |
| Context compaction | Claude Code (5 strategies) | M6/S03 |
| HEARTBEAT.md | Paperclip RFC #206 | M7/S01 |
| Goal hierarchy | Paperclip | M7/S02 |
| Never-stop philosophy | Autoresearch (Karpathy) | M7/S01 |
| Complexity routing | GSD 2 | Execution strategy |
| Operational learning | GStack | M3/S01 |
| Frozen snapshot | Hermes | M1/S02-T02 |
| Completion auto-routing | Middleman | M2/S03-T03 |

---

## WHAT WE DELIBERATELY SKIP

These features exist in competitor projects but are NOT worth building now:

| Feature | Why Skip |
|---------|----------|
| Gateway WebSocket server (OpenClaw) | Overkill for single-user agent. Our tmux session works. |
| Companion apps (OpenClaw) | No mobile app needed — iPhone Shortcuts via SSH suffices. |
| RL training pipeline (Hermes) | Requires GPU infrastructure we don't have. Skill auto-creation is enough. |
| Python RPC zero-context tools (Hermes) | Clever but complex. Sub-agents handle multi-step chains. |
| Containerization (Hermes) | Single Mac Mini. Containerize when we need multi-machine. |
| Company orchestration (Paperclip) | Alba IS the company. No need for multi-agent org chart yet. |
| Skill marketplace (OpenClaw ClawHub) | No external users. Auto-generated skills are internal only. |
| Profile system (Hermes) | Single agent. Profiles matter when running multiple instances. |
| Browse daemon (GStack) | Add later when we need visual QA. Not critical path. |
| Budget enforcement (Paperclip) | Single user, single budget. Track costs but don't enforce limits. |
