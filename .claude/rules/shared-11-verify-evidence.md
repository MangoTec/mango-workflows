# Verify Evidence Standards

**"Terminé" no significa "está verificado".** Antes de dar un cambio por listo (abrir PR,
cerrar una tarea), hay que producir **evidencia explícita** de que funciona — no una promesa.

## Regla

Antes de abrir un PR o declarar una tarea completa:

1. **Correr la verificación** real: el test command del repo (ver `openspec.config.yaml` /
   `package.json` / `composer.json`), y/o los comandos que ejercitan el cambio.
2. **Capturar el output real**: comandos ejecutados + resultado (tests que pasaron, salida relevante).
3. **Documentar la evidencia** en el PR (sección `## Testing`): qué se corrió, qué dio, qué quedó
   fuera de scope.
4. Si la verificación **no se puede correr** o **falla**: NO abrir el PR como si estuviera listo.
   Detenerse y reportar (`status: needs-human` / `risk`), ver `10-result-contract`.

## Prohibido

- "Debería andar" / "creo que funciona" sin evidencia.
- Sección `## Testing` con placeholders (`[How to verify]`) en vez de output real.
- Marcar "done" sin tests cuando el cambio los requiere (ver `03-tdd-standards`).

## Por qué

Cuántas veces un agente dijo "listo, funciona" y al correrlo explotaba. La evidencia cambia
la conversación con el revisor: en vez de "creo que está", entregás "esto se verificó así".
En code review eso vale oro y ahorra ida y vuelta.
