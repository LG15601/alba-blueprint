---
name: tool-discover
description: "Detect and register new tools when installed. Triggered by PostToolUse hook on brew install, npm install -g, pip install."
disable-model-invocation: true
user-invocable: false
allowed-tools:
  - Read
  - Write
  - Bash
---

# Tool Discovery

When a new tool is installed, update the registry.

## Detection
Parse the tool use output for installation patterns:
- `brew install X` → new CLI tool
- `npm install -g X` → new Node.js CLI
- `pip install X` → new Python tool
- `claude mcp add X` → new MCP server
- `npx skills add X` → new skill

## Registration
1. Get tool version: `X --version`
2. Get tool path: `which X`
3. Determine purpose from `X --help | head -5`
4. Add entry to ~/.alba/tool-registry.json
5. Log discovery in agent memory

## Registry Format
```json
{
  "tool_name": {
    "version": "x.y.z",
    "path": "/path/to/binary",
    "purpose": "One-line description",
    "installed": "2026-04-01",
    "type": "cli|mcp|skill|plugin"
  }
}
```
