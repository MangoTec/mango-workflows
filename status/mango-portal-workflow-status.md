# Workflow Status - MangoTec/mango-portal

Generated: 2026-04-20 18:00:40 CST

## Visual Overview

```mermaid
flowchart LR
  subgraph W0[Wave 0]
    I23["#23 feat: Foundation — copy mango-cobr\n[OPEN]"]:::inprogress
    G24["#24 Gate"]:::done
    I23 --> G24
  end
  subgraph W1[Wave 1]
    I6["#6 feat: Custom error boundary, 404 p\n[OPEN]"]:::inprogress
    I7["#7 feat: Reusable empty state compone\n[OPEN]"]:::inprogress
    I18["#18 feat: Add Select, Tooltip, Dialog \n[OPEN]"]:::inprogress
    I14["#14 feat: Breadcrumbs navigation compo\n[OPEN]"]:::inprogress
    I15["#15 feat: Dynamic page titles and meta\n[OPEN]"]:::inprogress
    I16["#16 feat: Loading skeleton UI (loading\n[OPEN]"]:::inprogress
    I20["#20 refactor: Extract reusable Paginat\n[OPEN]"]:::inprogress
    G25["#25 Gate"]:::neutral
    I6 --> G25
    I7 --> G25
    I18 --> G25
    I14 --> G25
    I15 --> G25
    I16 --> G25
    I20 --> G25
  end
  subgraph W2[Wave 2]
    I1["#1 feat: Payment detail view /pagos/[\n[OPEN]"]:::blocked
    I2["#2 feat: Facturas (supplier invoices)\n[OPEN]"]:::blocked
    I3["#3 feat: Créditos (payment credits) p\n[OPEN]"]:::blocked
    I12["#12 feat: Penalizaciones page with sup\n[OPEN]"]:::blocked
    I13["#13 feat: Supplier profile/details pag\n[OPEN]"]:::blocked
    I8["#8 feat: Dashboard payment volume cha\n[OPEN]"]:::blocked
    I9["#9 feat: Customer dropdown filter on \n[OPEN]"]:::blocked
    G26["#26 Gate"]:::neutral
    I1 --> G26
    I2 --> G26
    I3 --> G26
    I12 --> G26
    I13 --> G26
    I8 --> G26
    I9 --> G26
  end
  subgraph W3[Wave 3]
    I4["#4 feat: Export payments to CSV/Excel\n[OPEN]"]:::blocked
    I5["#5 feat: Responsive mobile layout wit\n[OPEN]"]:::blocked
    I10["#10 feat: Quick date range presets for\n[OPEN]"]:::blocked
    I11["#11 feat: Sortable columns on payment \n[OPEN]"]:::blocked
    I21["#21 feat: Dark mode toggle and support\n[OPEN]"]:::blocked
    G27["#27 Gate"]:::neutral
    I4 --> G27
    I5 --> G27
    I10 --> G27
    I11 --> G27
    I21 --> G27
  end
  subgraph W4[Wave 4]
    I17["#17 fix: Sign out uses form POST but n\n[OPEN]"]:::blocked
    I19["#19 docs: Rewrite README.md with proje\n[OPEN]"]:::blocked
  end
  G24 --> I6
  G25 --> I1
  G26 --> I4
  G27 --> I17
  classDef done fill:#b7f7bf,stroke:#2e7d32,color:#111;
  classDef inprogress fill:#ffe082,stroke:#ef6c00,color:#111;
  classDef ready fill:#bbdefb,stroke:#1565c0,color:#111;
  classDef blocked fill:#eeeeee,stroke:#616161,color:#111;
  classDef failed fill:#ffcdd2,stroke:#c62828,color:#111;
  classDef neutral fill:#f3e5f5,stroke:#6a1b9a,color:#111;
```

## Open PRs

| PR | Title | Author | Draft | Link |
|---|---|---|---|---|
| #35 | refactor: Extract reusable Pagination component | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/35) |
| #34 | feat: loading skeleton UI (loading.tsx) for all routes | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/34) |
| #33 | feat: Dynamic page titles and metadata | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/33) |
| #32 | feat: Breadcrumbs navigation component | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/32) |
| #31 | feat: error boundaries, 404 page, and reusable ErrorState component | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/31) |
| #30 | feat: Add Select, Tooltip, Dialog UI components | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/30) |
| #29 | feat: reusable EmptyState component + payments table integration | app/copilot-swe-agent | true | [open](https://github.com/MangoTec/mango-portal/pull/29) |

## Recent Runs

| Workflow | Status | Conclusion | Event | Branch | Link |
|---|---|---|---|---|---|
| Assign Agent | completed | success | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696351683) |
| Assign Agent | completed | success | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696349862) |
| Assign Agent | completed | success | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696348103) |
| Wave Gate — Unlock Next Wave | completed | skipped | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696351667) |
| Wave Gate — Unlock Next Wave | completed | skipped | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696349857) |
| Wave Gate — Unlock Next Wave | completed | skipped | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696348105) |
| On Issue Close — Check Wave Completion | completed | success | issues | main | [run](https://github.com/MangoTec/mango-portal/actions/runs/24615856054) |
| CI | completed | action_required | pull_request | copilot/refactor-extract-pagination-component | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696653104) |
| CI | completed | action_required | pull_request | copilot/feat-loading-skeleton-ui | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696625342) |
| CI | completed | action_required | pull_request | copilot/add-select-tooltip-dialog-components | [run](https://github.com/MangoTec/mango-portal/actions/runs/24696511337) |
