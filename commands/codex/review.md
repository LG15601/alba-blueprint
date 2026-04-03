Run an AI-powered code review using the Codex CLI.

Execute the review script with any arguments the user provided after the slash command:

```bash
bash ~/.claude/skills/codex/scripts/codex-review.sh $ARGUMENTS
```

If no arguments are given, run without arguments (defaults to `--uncommitted`).

Supported arguments:
- `--uncommitted` — review uncommitted changes (default)
- `--base <branch>` — review diff against a base branch
- `--commit <sha>` — review a specific commit
- Free-form text — passed as a review prompt

After the review completes, summarize the key findings for the user.
If the script fails, report the error message and suggest fixes (missing codex CLI, auth issues).
