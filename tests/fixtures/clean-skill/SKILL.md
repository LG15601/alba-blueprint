---
name: clean-test-skill
version: 1.0.0
description: A benign skill for testing false-positive rates
---

# Clean Test Skill

A simple, safe skill that demonstrates normal markdown content.

## Overview

This skill helps users manage their task lists. It provides commands
for adding, removing, and listing tasks in a local database.

## Usage

```bash
echo "Hello, world!"
ls -la ~/Documents
cat README.md
```

## Features

- Task creation with due dates
- Priority levels (low, medium, high)
- Markdown export of task lists
- Local SQLite storage

## Example Output

```
Tasks for today:
  1. [x] Review pull request
  2. [ ] Write documentation
  3. [ ] Update changelog
```

## Notes

This skill stores data in `~/.local/share/tasks/` and does not
require any network access or API keys.
