Run an autonomous fix using the Codex CLI in full-auto mode.

Execute the rescue script with the user's task description:

```bash
bash ~/.claude/skills/codex/scripts/codex-rescue.sh $ARGUMENTS
```

The user must provide a task description. If they didn't, ask them what they want Codex to fix.

Supported arguments:
- `--dir <path>` — set the working directory for the fix
- Everything else is treated as the task description

After execution, report what Codex did — files changed, tests fixed, etc.
If the script fails, report the error and suggest fixes.

⚠️ This runs Codex in `--full-auto` mode, which can modify files autonomously. The user should review changes after execution.
