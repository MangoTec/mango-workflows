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
  "version": "3.0.0",
  "agent": {
    "primary": "copilot",        // Proveedor inicial
    "fallback": "codex",         // Alternativa en retry
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
    "level": "human-gate-pr",    // human revisa PRs
    "autoAssignAgent": true,
    "autoMerge": false,
    "waveGateRequired": true
  },
  "waves": {
    "0": [1],                    // Wave 0: issue #1
    "1": [2, 3, 4]              // Wave 1: issues #2, #3, #4 (dependen de wave 0)
  },
  "dependencies": {
    "1": [],
    "2": [1],
    "3": [1],
    "4": [1]
  },
  "waveGates": {
    "0": 10,                     // Issue #10 es el gate de wave 0
    "1": 11
  }
}
```

> **Backward compatibility**: v3 es compatible con v2 (`agent.primary` fallback a `agent.provider`, `agent.providers.copilot.username` fallback a `agent.copilot.username`).

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
