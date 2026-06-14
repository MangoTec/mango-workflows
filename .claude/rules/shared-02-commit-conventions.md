---
description: Git commit conventions for all Mango repositories
globs: "**"
---

# Commit Conventions

- Format: Angular naming convention → `type(scope): lowercase description`
- Types: fix, feat, chore, test, refactor, docs
- Scope: module/area affected in parentheses (e.g., healthcheck, stp-monitor, deploy)
- Description: lowercase, English, no period at end
- PR title MUST match the commit message exactly
- Squash merge only — all repos configured for squash merge with PR title as commit title
- Branch naming: `type/short-description` (e.g., `feat/stp-movements`, `fix/sidebar-permissions`)
