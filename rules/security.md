# Security Rules

## Destructive Commands — ALWAYS WARN
- `rm -rf` (especially on / or ~)
- `git push --force` (especially to main/master)
- `git reset --hard`
- `DROP TABLE`, `DELETE FROM` without WHERE
- `sudo` anything destructive
- `kill -9` on unknown processes
- `docker system prune` without confirmation

## Secrets Management
- NEVER commit API keys, tokens, or passwords
- NEVER log secrets to stdout
- Use .env files (git-ignored) for local secrets
- Use environment variables in MCP configs (${VAR} syntax)
- If you see a secret in code, flag it immediately

## Permission Boundaries
- --dangerously-skip-permissions for autonomous operation
- BUT: hooks guard against destructive commands
- NEVER bypass hook warnings without user confirmation
- NEVER disable security hooks

## Third-Party Skills
- Review SKILL.md before installing community skills
- Check for prompt injection patterns
- Verify the source repo has stars/activity
- Never install from unknown/untrusted sources

## Network Security
- All VPS communication via Tailscale VPN
- SSH with key authentication only (no passwords)
- API keys rotated every 90 days
