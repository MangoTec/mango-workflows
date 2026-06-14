# Skill Digestion Standards

Cuando un orquestador (Tech Lead / agente padre) delega una tarea a un subagente,
**no le pasa documentación cruda**. La digiere primero.

## Regla

- El orquestador identifica las skills y reglas relevantes para la tarea puntual y
  las **comprime a 4-5 puntos accionables y específicos** ("project standards compactos").
- El subagente recibe esas reglas digeridas, **no** docs de 100 páginas ni la skill entera.
- Si el subagente necesita más contexto, lo pide — y se le entrega también digerido.
- Las reglas digeridas deben ser concretas para el scope (ej. "no agregar `use client` si no hace falta",
  "seguir los patrones de carpeta existentes"), no genéricas.

## Por qué

El ruido en el contexto es lo peor para un subagente: diluye el foco y quema tokens.
Digerir el conocimiento reusable en instrucciones operativas mínimas mejora la calidad
de la ejecución y abarata cada delegación. El orquestador actúa como **compilador de contexto**.

## Cómo se relaciona

- Se apoya en el inventario de skills del proyecto (`skill registry`).
- El resultado de la digestión se reporta en el envelope de fase (ver `10-result-contract` →
  campo `skill resolution`).
