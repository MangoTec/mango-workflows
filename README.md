# Agent Workflows

Reusable GitHub Actions workflows for orchestrating AI coding agents across Mango repos.

## Architecture

```
┌─ Consumer Repo ──────────────┐     ┌─ agent-workflows (shared) ─┐
│                               │     │                             │
│  pipeline-config.json         │     │  assign-agent.yml           │
│  thin caller workflows ──────────▶  │  wave-gate.yml              │
│  codex-implement.yml (local)  │     │  on-issue-close.yml         │
│  agent-ci-fix.yml (local)     │     │  agent-retry.yml            │
│  ci.yml (local)               │     │                             │
│  copilot-setup-steps.yml      │     └─────────────────────────────┘
└───────────────────────────────┘
```

## How It Works

1. Issues get `status:ready` label → **assign-agent** validates spec + routes to AI provider
2. Agent implements → creates PR → CI runs
3. If agent fails → `status:failed` → **agent-retry** switches provider + re-triggers
4. If CI fails on agent PR → **agent-ci-fix** (local) extracts error + notifies
5. When issue closes → **on-issue-close** checks if wave is complete
6. When wave completes + gate approved → **wave-gate** unlocks next wave

## Setup

### 1. pipeline-config.json

Create `.github/pipeline-config.json` in your repo. See schema below.

### 2. Thin caller workflows

Each consumer repo adds short workflows that delegate to these shared ones:

```yaml
# .github/workflows/assign-agent.yml
name: Assign Agent
on:
  issues:
    types: [labeled]
jobs:
  assign:
    if: github.event.label.name == 'status:ready'
    permissions:
      issues: write
      contents: read
      actions: write
    uses: MangoTec/agent-workflows/.github/workflows/assign-agent.yml@v1
    with:
      issue-number: "${{ github.event.issue.number }}"
    secrets: inherit
```

### 3. Required secrets

| Secret | Used by | Required |
|---|---|---|
| `SLACK_WEBHOOK_URL` | All workflows | Optional |
| `GH_PAT_PORTAL` | assign-agent (Copilot assignment) | Optional |
| `OPENAI_API_KEY` | codex-implement (local) | If using Codex |

### 4. Required labels

Create these labels in your repo:

| Label | Purpose |
|---|---|
| `status:ready` | Issue ready for agent |
| `status:in-progress` | Agent working |
| `status:blocked` | Blocked by dependencies |
| `status:failed` | Agent failed |
| `status:spec-invalid` | Spec didn't pass linter |
| `needs-human` | Max retries exceeded |
| `wave-gate` | Wave QA gate issue |
| `gate:approved` | Wave gate approved |
| `provider-override:copilot` | Force Copilot on retry |
| `provider-override:codex` | Force Codex on retry |
| `retry:1`, `retry:2` | Retry count tracking |

## Config Schema (v3)

```json
{
  "version": "3.0.0",
  "agent": {
    "primary": "copilot",
    "fallback": "codex",
    "maxRetries": 2,
    "providers": {
      "copilot": {
        "username": "copilot-swe-agent"
      },
      "codex": {
        "model": "gpt-5.4",
        "effort": "medium",
        "sandbox": "workspace-write",
        "promptTemplate": ".github/codex/prompts/implement.md"
      }
    }
  },
  "specLinter": {
    "minBodyLength": 200,
    "requiredSections": ["Requirements", "Acceptance Criteria"]
  },
  "autonomy": {
    "level": "human-gate-pr",
    "autoAssignAgent": true,
    "autoMerge": false,
    "waveGateRequired": true
  },
  "waves": {
    "0": [1],
    "1": [2, 3, 4]
  },
  "dependencies": {
    "1": [],
    "2": [1],
    "3": [1],
    "4": [1]
  },
  "waveGates": {
    "0": 10,
    "1": 11
  }
}
```

### Backward Compatibility

v3 config is backward compatible with v2:
- `agent.primary` falls back to `agent.provider`
- `agent.providers.copilot.username` falls back to `agent.copilot.username`
- `specLinter` defaults to `{ minBodyLength: 200, requiredSections: ["Requirements", "Acceptance Criteria"] }`

## Local Workflows (per repo)

These stay in each consumer repo because they have project-specific logic:

### codex-implement.yml
Runs OpenAI Codex. Includes project-specific setup (npm, prisma, etc.) and prompt templates.

### agent-ci-fix.yml
Detects CI failures on agent PRs. Extracts errors. Comments on PR + linked issue.
Adds `status:failed` to trigger retry loop.

### ci.yml
Standard CI checks. Project-specific.

### copilot-setup-steps.yml
Copilot agent setup. Project-specific dependencies.

## Flow Diagram

```
  Issue created
       │
       ▼
  status:ready label
       │
       ▼
  ┌─────────────┐
  │ assign-agent │──spec invalid──▶ status:spec-invalid
  │  (shared)    │
  └──────┬───────┘
         │
    ┌────┴────┐
    ▼         ▼
 copilot    codex
 assigned   dispatched
    │         │
    ▼         ▼
  PR created ◄─────────┐
    │                    │
    ▼                    │
  CI runs               │
    │                    │
 ┌──┴──┐                │
 ▼     ▼                │
pass  fail              │
 │     │                │
 ▼     ▼                │
merge  agent-ci-fix     │
       │                │
       ▼                │
  status:failed         │
       │                │
       ▼                │
  ┌─────────────┐       │
  │ agent-retry  │──────┘
  │  (shared)    │  (adds status:ready
  └──────────────┘   with fallback provider)
```
