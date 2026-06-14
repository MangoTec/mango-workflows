# Result Contract Standards

Entre fases de un flujo agéntico (proposal → spec → design → tasks → apply → verify)
**no se pasa prosa libre**. Cada fase devuelve un *envelope* consistente, parseable y auditable.

## El envelope

Cada fase completada devuelve:

| Campo | Qué contiene |
|---|---|
| `status` | `ok` / `blocked` / `needs-human` |
| `executive summary` | Resumen de 1-3 líneas de lo que se hizo |
| `artifact(s)` | Qué se produjo y dónde (paths, PRs, archivos) |
| `next recommended step` | La siguiente acción sugerida |
| `risk` | Riesgos detectados (o "ninguno") |
| `skill resolution` | Qué skills se aplicaron, cuáles cayeron en fallback (ver `09-skill-digestion`) |

## Por qué

Un contrato es predecible y le permite al orquestador **decidir sin interpretar una novela**:
si hay riesgo, pausa; si falta un artefacto, se detiene; si el siguiente paso requiere decisión
humana, pregunta. Sin contrato, el orquestador adivina — y un Tech Lead que adivina es un proyecto
que se descarrila.

## Regla

- Toda fase relevante (las que producen estado recuperable) cierra con este envelope.
- El `status = needs-human` es una señal explícita de gate, no un error.
- El envelope es la evidencia que la fase `verify` audita.
