# Mango Workflows

Reusable GitHub Actions workflows para orquestar agentes de AI coding y automatización compartida en los repos de [MangoTec](https://github.com/MangoTec).

## Workflows compartidos

| Workflow | Trigger | Descripción |
|---|---|---|
| `assign-agent.yml` | `status:ready` label | Valida spec del issue, rutea al proveedor de AI (Copilot o Codex) |
| `agent-retry.yml` | `status:failed` label | Reintenta con proveedor alternativo, trackea reintentos, escala a humano después de N fallos |
| `on-issue-close.yml` | Issue cerrado | Verifica si el wave actual está completo, notifica al gate issue |
| `wave-gate.yml` | `gate:approved` label | Desbloquea issues del próximo wave |

## Arquitectura

```
┌─ Repo consumidor ────────────┐      ┌─ mango-workflows (shared) ─┐
│                               │      │                             │
│  pipeline-config.json         │      │  assign-agent.yml           │
│  thin callers ───────────────────▶   │  agent-retry.yml            │
│                               │      │  on-issue-close.yml         │
│  codex-implement.yml (local)  │      │  wave-gate.yml              │
│  agent-ci-fix.yml   (local)   │      │                             │
│  ci.yml             (local)   │      └─────────────────────────────┘
│  copilot-setup-steps.yml      │
└───────────────────────────────┘
```

Los **thin callers** son workflows de ~10 líneas en cada repo que delegan a los workflows compartidos. Los workflows **locales** contienen lógica específica del proyecto (setup, CI, prompts).

## Flujo completo

```
  Issue creado
       │
       ▼
  label status:ready
       │
       ▼
  ┌──────────────┐
  │ assign-agent │──spec inválida──▶ status:spec-invalid
  └──────┬───────┘
         │ spec válida
    ┌────┴────┐
    ▼         ▼
 Copilot    Codex
 (assign)   (dispatch)
    │         │
    ▼         ▼
  PR creado ◄───────────┐
    │                    │
    ▼                    │
  CI corre               │
    │                    │
 ┌──┴──┐                │
 ▼     ▼                │
pass  fail              │
 │     │                │
 ▼     ▼                │
merge  agent-ci-fix     │
       │  (local)       │
       ▼                │
  status:failed         │
       │                │
       ▼                │
  ┌──────────────┐      │
  │ agent-retry  │──────┘ (switch provider + status:ready)
  └──────────────┘
         │
     max retries?
         │
         ▼
    needs-human
```

## Setup en un repo nuevo

### 1. Crear `pipeline-config.json`

En `.github/pipeline-config.json`:

```jsonc
{
  "version": "4.0.0",

  // ─── Mission (v4) ───
  // Unit of work. One mission = one automated task launched with mango-workflows.
  // Optional — omit for v3 backward compatibility.
  "mission": {
    "id": "portal-mvp",                           // Unique slug
    "name": "Portal MVP — Estado de Cuenta",       // Human-readable
    "specSource": "mango-engineering/specs/mango-portal/001-portal-mvp"  // Where the spec lives
  },

  // ─── Agent config (unchanged from v3) ───
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

  // ─── Spec linter (v4: enhanced) ───
  "specLinter": {
    "minBodyLength": 200,
    "requiredSections": ["Requirements", "Acceptance Criteria"],
    // v4: validate that referenced files exist in the repo
    "validateFileRefs": true,
    // v4: require spec to reference the mission source-of-truth
    "requireSpecSource": true
  },

  // ─── Autonomy (v4: per-wave gates replace global boolean) ───
  "autonomy": {
    "level": "human-gate-pr",
    "autoAssignAgent": true,
    "autoMerge": false
    // NOTE: "waveGateRequired" is still supported for v3 compat.
    // If "waves" uses object format (v4), per-wave gate config takes precedence.
  },

  // ─── Waves (v4: object format with per-wave config) ───
  // Each wave is an object with issues, gate type, and optional verify hooks.
  // Gate types: "auto" | "human" | "verify-then-auto"
  //   - auto: next wave unlocks immediately when all issues close
  //   - human: gate issue gets notified, needs gate:approved label
  //   - verify-then-auto: runs verify hooks first; if pass → auto-unlock; if fail → re-open issues with error context
  "waves": {
    "0": {
      "issues": [23],
      "gate": "human"                              // Foundation wave — always review
    },
    "1": {
      "issues": [6, 7, 18, 14, 15, 16, 20],
      "gate": "verify-then-auto",                  // Trust CI + verify scripts
      "verify": ["build", "test"]                  // References to verification.hooks keys
    },
    "2": {
      "issues": [1, 2, 3, 12, 13, 8, 9],
      "gate": "auto"                               // Low-risk, auto-unlock
    },
    "3": {
      "issues": [4, 5, 10, 11, 21],
      "gate": "human"                              // Final review before last wave
    },
    "4": {
      "issues": [17, 19],
      "gate": "auto"
    }
  },

  // ─── Verification hooks (v4: new) ───
  // Named hooks that waves can reference in their "verify" array.
  // Each hook is a shell command that runs in the repo root.
  // Exit 0 = pass, non-zero = fail (error output injected into issue comment).
  "verification": {
    "hooks": {
      "build": "npm run build",
      "test": "npm run test",
      "typecheck": "npx tsc --noEmit",
      "custom": "./scripts/verify-mission.sh"
    }
  },

  // ─── Cleanup policy (v4: new) ───
  "cleanup": {
    "deleteMergedTaskBranches": true,              // Delete task branches after consolidated PR merges
    "closeResolvedGateIssues": true,               // Close gate issues when their wave is done
    "deleteConsolidatedBranch": false,              // Keep wave-N/consolidate branches (history)
    "removeLabelsOnComplete": true                  // Strip pipeline labels from completed issues
  },

  // ─── Dependencies (unchanged) ───
  "dependencies": {
    "23": [],
    "6":  [23],
    "7":  [23]
  },

  // ─── Wave gates (v3 compat — optional in v4 if using object waves) ───
  "waveGates": {
    "0": 24,
    "1": 25
  }
}
```

> **Backward compatibility**: v4 is fully backward-compatible with v3.
> - If `waves` values are arrays (v3 format), `autonomy.waveGateRequired` controls gate behavior globally.
> - If `waves` values are objects (v4 format), per-wave `gate` config takes precedence.
> - `mission`, `verification`, and `cleanup` blocks are optional — workflows use sensible defaults when absent.
> - v3→v2 compat is preserved (`agent.primary` fallback to `agent.provider`, etc.).

### 2. Agregar thin callers

Crear estos 3 archivos en `.github/workflows/`:

<details>
<summary><code>assign-agent.yml</code></summary>

```yaml
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
    uses: MangoTec/mango-workflows/.github/workflows/assign-agent.yml@v1
    with:
      issue-number: "${{ github.event.issue.number }}"
    secrets: inherit
```
</details>

<details>
<summary><code>agent-retry.yml</code></summary>

```yaml
name: Agent Retry
on:
  issues:
    types: [labeled]
jobs:
  retry:
    if: github.event.label.name == 'status:failed'
    permissions:
      issues: write
      contents: read
      actions: write
    uses: MangoTec/mango-workflows/.github/workflows/agent-retry.yml@v1
    with:
      issue-number: "${{ github.event.issue.number }}"
    secrets: inherit
```
</details>

<details>
<summary><code>on-issue-close.yml</code></summary>

```yaml
name: On Issue Close
on:
  issues:
    types: [closed]
jobs:
  check-wave:
    permissions:
      issues: write
      contents: read
    uses: MangoTec/mango-workflows/.github/workflows/on-issue-close.yml@v1
    with:
      closed-issue: "${{ github.event.issue.number }}"
    secrets: inherit
```
</details>

### 3. Crear labels

| Label | Color | Propósito |
|---|---|---|
| `status:ready` | `#0E8A16` | Issue listo para agente |
| `status:in-progress` | `#FBCA04` | Agente trabajando |
| `status:blocked` | `#D93F0B` | Bloqueado por dependencias |
| `status:failed` | `#B60205` | Agente falló |
| `status:spec-invalid` | `#E4E669` | Spec no pasó validación |
| `needs-human` | `#D93F0B` | Máximo de reintentos alcanzado |
| `wave-gate` | `#C5DEF5` | Issue de gate de wave |
| `gate:approved` | `#0E8A16` | Gate aprobado |
| `provider-override:copilot` | `#1D76DB` | Forzar Copilot en retry |
| `provider-override:codex` | `#5319E7` | Forzar Codex en retry |
| `retry:1`, `retry:2` | `#BFDADC` | Tracking de reintentos |

### 4. Configurar secrets (opcionales)

| Secret | Usado por | Necesario |
|---|---|---|
| `SLACK_WEBHOOK_URL` | Todos (notificaciones) | Opcional |
| `GH_PAT_PORTAL` | assign-agent (asignar Copilot) | Opcional |
| `OPENAI_API_KEY` | codex-implement (local) | Solo si usa Codex |

## Workflows locales (por repo)

Estos quedan en cada repo consumidor porque contienen lógica específica del proyecto:

| Workflow | Descripción |
|---|---|
| `codex-implement.yml` | Ejecuta OpenAI Codex con setup y prompts del proyecto |
| `agent-ci-fix.yml` | Detecta fallos de CI en PRs de agentes, extrae errores, comenta en PR/issue, agrega `status:failed` |
| `ci.yml` | CI estándar del proyecto |
| `copilot-setup-steps.yml` | Setup de dependencias para Copilot agent |

## Repos consumidores

- [mango-portal](https://github.com/MangoTec/mango-portal)

## Versionado

Se usa git tags (`v1`, `v2`, etc.). Los thin callers referencian `@v1`. Para actualizar todos los repos, mover el tag:

```bash
git tag -f v1 && git push origin v1 --force
```
