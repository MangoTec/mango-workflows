---
description: Engram persistent memory protocol — mandatory for all AI sessions
globs: "**"
---

# Engram Memory Protocol

You MUST use Engram MCP tools proactively in every session.

## Protocol

1. `mem_context` — call at session start to recover previous context
2. `mem_save` — call IMMEDIATELY after EACH significant action (not batched)
3. `mem_search` — call before starting work that might overlap past sessions
4. `mem_session_summary` — call before ending a session

## Save triggers (save after ANY of these)

- Bug fix completed
- Architecture or design decision made
- Config/infra change
- Non-obvious codebase discovery
- New pattern or convention established
- PR created or merged
- File edited or created

## Rules

- Do NOT batch saves — save after EACH item
- Do NOT wait for the user to remind you
