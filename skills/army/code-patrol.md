---
name: code-patrol
description: |
  Review PRs, check CI status, fix simple bugs across Orchestra's repos.
  Automated code quality patrol that monitors GitHub activity, reviews open PRs,
  identifies failing CI, and can fix simple issues autonomously. Use when asked
  to "check repos", "code patrol", "review PRs", or on daily cron.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Agent
  - Glob
  - Grep
---

# Code Patrol -- Multi-Repo Code Quality Monitor

Automated patrol across Orchestra Intelligence's repositories. Reviews PRs,
monitors CI, identifies issues, and fixes simple bugs autonomously.

## Arguments
- `/code-patrol` -- full patrol across all repos
- `/code-patrol [repo]` -- patrol specific repo
- `/code-patrol prs` -- only review open PRs
- `/code-patrol ci` -- only check CI status
- `/code-patrol fix [repo] [issue]` -- fix a specific issue

## Monitored Repositories

```bash
# List all org repos
gh repo list orchestraintelligence --limit 20 --json name,url,updatedAt 2>/dev/null
# Or check configured repo list
cat ~/.alba/config/repos.json 2>/dev/null || echo "Using default repo list"
```

Default repo list (update via config):
1. alba-blueprint -- Alba agent infrastructure
2. orchestra-website -- Main website
3. orchestra-app -- Client dashboard
4. orchestra-api -- Backend API
5. orchestra-crm -- CRM system
6. orchestra-docs -- Documentation
7. orchestra-automations -- Client automation scripts
8. orchestra-billing -- Billing system
9. orchestra-infra -- Infrastructure/DevOps

## Step 1: CI Status Check

For each repo:
```bash
REPO="orchestraintelligence/[repo-name]"
# Recent workflow runs
gh run list --repo "$REPO" --limit 5 --json status,conclusion,name,headBranch,updatedAt 2>/dev/null
# Failed runs detail
gh run list --repo "$REPO" --status failure --limit 3 --json databaseId,name,headBranch 2>/dev/null
```

### CI Triage
- **Red (failing on main)**: CRITICAL -- investigate immediately
- **Yellow (failing on branch)**: Normal -- review PR context
- **Green (all passing)**: OK -- log and move on

For each CRITICAL failure:
```bash
# Get failure logs
gh run view [run-id] --repo "$REPO" --log-failed 2>/dev/null | tail -50
```

## Step 2: Open PR Review

For each repo:
```bash
gh pr list --repo "$REPO" --state open --json number,title,author,createdAt,updatedAt,mergeable,reviewDecision,labels 2>/dev/null
```

### PR Review Checklist

For each open PR, evaluate:

1. **Staleness**: Created 3+ days ago without activity? Flag for attention.
2. **Size**: Files changed, lines added/removed. Over 500 lines? Flag as oversized.
3. **Tests**: Does the diff include test changes? If code changed but no tests, flag.
4. **CI Status**: All checks passing?
5. **Merge conflicts**: Is it mergeable?
6. **Security scan**:
   - Secrets in diff (API keys, tokens, passwords)
   - SQL injection patterns (string concatenation in queries)
   - Unvalidated user input in API routes
   - Dependencies with known vulnerabilities
7. **Code quality**:
   - Console.log / print statements left in
   - Commented-out code blocks
   - TODO/FIXME without issue reference
   - Hardcoded values that should be config

### Review Output Per PR
```
PR #[number]: [title]
Repo: [repo]
Author: [author] | Age: [days] | Size: +[add]/-[del] ([files] files)
CI: [pass/fail] | Mergeable: [yes/no]
Issues: [list of flagged issues]
Verdict: APPROVE / REQUEST_CHANGES / NEEDS_ATTENTION
```

## Step 3: Autonomous Fixes

Alba can fix these automatically (create PR):
- Linting errors (formatting, import order)
- Type errors with obvious fixes
- Dependency version bumps (patch only)
- Stale lock files
- Missing environment variable documentation
- README typos

Alba must NOT fix these autonomously:
- Logic bugs (needs understanding of intent)
- Security vulnerabilities (needs careful review)
- Database migration issues
- Breaking API changes
- Anything affecting client-facing behavior

### Fix Workflow
```bash
# Clone/pull the repo
cd /tmp && gh repo clone "$REPO" -- --depth 1
cd [repo-name]
git checkout -b alba/fix-[description]
# Make the fix
# ...
git add -A && git commit -m "fix: [description]"
gh pr create --title "fix: [description]" --body "Automated fix by Alba code-patrol.

Changes:
- [what was fixed]

Tested:
- [how it was verified]"
```

## Step 4: Dependency Audit

Weekly check (or on demand):
```bash
# For Node.js repos
cd [repo] && npm audit --json 2>/dev/null | head -100
# For Python repos
cd [repo] && pip-audit --json 2>/dev/null | head -100
```

Flag:
- Critical/high severity vulnerabilities
- Dependencies with no recent updates (2+ years)
- Unused dependencies (if detectable)

## Step 5: Code Quality Metrics

Compute per-repo health score:

| Metric              | Weight | Score Range |
|---------------------|--------|-------------|
| CI pass rate (7d)   | 25%    | 0-100       |
| Open PR age (avg)   | 20%    | 0-100       |
| Test coverage       | 20%    | 0-100       |
| Dependency health   | 15%    | 0-100       |
| Code freshness      | 10%    | 0-100       |
| Documentation       | 10%    | 0-100       |

Overall repo score: weighted average, 0-100.

## Step 6: Report

### Patrol Report
```bash
mkdir -p ~/.alba/code-patrol
echo "[report]" > ~/.alba/code-patrol/YYYY-MM-DD-patrol.json
```

### Summary for Telegram (French)
```
CODE PATROL -- [DATE]

REPOS: [N] surveilles
CI: [X] OK, [Y] en echec
PRs OUVERTS: [N] ([M] a traiter)

ALERTES:
- [repo]: CI rouge sur main depuis [duration]
- [repo]: PR #[N] stale depuis [X] jours
- [repo]: Vulnerabilite [severity] dans [dep]

FIXES AUTOMATIQUES: [N]
- [repo]: [fix description] -> PR #[N]

SCORES SANTE:
- [repo]: [score]/100 ([trend])
- [repo]: [score]/100 ([trend])
...

Actions requises: [count]
```

## Orchestra Rules
- Never force-push to main/master on any repo
- Never merge PRs automatically (create, review, but Ludovic merges)
- Never commit secrets or credentials
- Autonomous fixes: only for non-breaking, non-client-facing changes
- Always run tests before creating fix PRs
- Security vulnerabilities: alert immediately via Telegram, do not just log
- Client repos (automations): extra caution, never touch without explicit instruction
- All commit messages in English
- PR descriptions in English with technical detail
- Use conventional commits: fix:, feat:, chore:, docs:, test:
