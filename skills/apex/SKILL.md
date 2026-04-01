---
name: apex
description: "10-step autonomous feature workflow: branch → analyze → plan → execute → validate → review → fix → test → verify → PR. Use when asked to build a feature end-to-end."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
---

# Apex Workflow

Autonomous 10-step feature implementation. Each step must pass before advancing.

## Steps

### 1. INIT
```bash
git checkout -b feature/FEATURE_NAME
```

### 2. ANALYZE
- Read relevant source files
- Understand existing patterns and conventions
- Identify all files that need changes
- Check for related tests

### 3. PLAN
Enter Plan mode. Design the implementation:
- What files to create/modify
- What the changes look like
- What tests to add
- Potential risks and edge cases

Present plan to user for approval before proceeding.

### 4. EXECUTE
Delegate to coder sub-agent (isolation: worktree):
- Implement the planned changes
- Follow project conventions
- Write clean, minimal code

### 5. VALIDATE
```bash
# Run linter
npm run lint 2>/dev/null || npx eslint . 2>/dev/null
# Run type checker
npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null
```
Fix any issues found.

### 6. REVIEW
Delegate to reviewer sub-agent:
- Security check
- Correctness check
- Convention check
- Simplicity check

### 7. FIX
Address all review findings. Re-run review if changes were significant.

### 8. TEST
```bash
npm test 2>/dev/null || npm run test 2>/dev/null
```
All tests must pass. Fix failures.

### 9. VERIFY
Manual verification against original requirements:
- Does it solve the stated problem?
- Are there edge cases missed?
- Is it production-ready?

### 10. PR
```bash
git add -A
git commit -m "feat: DESCRIPTION"
gh pr create --title "TITLE" --body "BODY"
```

## Rules
- Never skip a step
- If a step fails 3 times, escalate to user
- Each step produces a brief status update
- Total time: aim for under 30 minutes
