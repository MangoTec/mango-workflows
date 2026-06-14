# Review & Delivery Standards

Estas reglas protegen el tiempo del revisor humano y evitan el "AI slop" (PRs
gigantes generados por IA, imposibles de revisar bien). Las aplica el agente
`@delivery` y el check de CI `pr-size-check`.

## Review-risk gate

Antes de abrir un PR, evaluá el riesgo de review:

- **Umbral por defecto: ~400 líneas cambiadas** o **muchas áreas no relacionadas tocadas**.
- Archivos generados, lockfiles y código vendored NO cuentan para el umbral — marcalos pero no bloquees por ellos.
- Si se supera el umbral, NO abras un único PR enorme en silencio. Frená y proponé una estrategia de entrega.
- Siempre mostrá el conteo de líneas/áreas para que el humano decida con datos, no a ojo.

## Estrategias de entrega

| Estrategia | Cuándo | Cómo |
|---|---|---|
| **Single PR** | scope chico, bajo el umbral | flujo normal |
| **Stacked PRs** | cambio grande divisible en unidades lógicas | una branch por unidad, encadenadas; cada PR atómico y revisable |
| **Feature branch** | querés rollback limpio | encadenás sobre una branch de integración vacía; si algo falla, rollback de un solo merge |
| **Exception-OK** | el cambio no se puede dividir de forma sensata (ej. migración) | se acepta un PR grande SOLO con justificación humana explícita |

## Política de enforcement

- **CI advisory-first**: el check `pr-size-check` mide el diff y **comenta** si supera el umbral. NO falla el PR.
- El umbral es configurable por repo vía `env` del workflow (un repo migración-pesada puede subirlo).
- Subir el check a **required** (que falle) es una decisión posterior, solo si los datos muestran que el problema existe.

## Por qué

Un PR de 1000 líneas no es productividad, es **deuda de revisión** que paga otro
humano. Partir el trabajo en unidades atómicas, testeables y entendibles es parte
del trabajo de ingeniería, no un extra opcional.
