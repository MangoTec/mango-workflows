---
description: Secrets management with 1Password CLI for the Mango agentic layer
globs: "**"
---

# Secrets — 1Password (capa agéntica)

- Auth del `op` CLI (1Password CLI, ya instalado v2.34) es **per-usuario vía integración desktop biométrica**: 1Password app → Settings → Developer → "Integrate with CLI" + biometric unlock. No se comparten tokens ni service accounts entre personas.
- Referenciá secretos con el patrón `op://Vault/Item/field` y resolvélos en runtime con `op run -- <comando>` (inyecta env vars efímeras) o `op read <ref>`; nunca los pegues en el comando ni en archivos versionados.
- NUNCA hardcodees ni commitees secretos (API keys, tokens, credenciales). Los `.env` están gitignored y deben quedarse así; los archivos de ejemplo (`.env.example`) llevan solo placeholders o refs `op://`.
- PROHIBIDO usar `op read` para volcar a texto plano credenciales sensibles de producción (DB prod, STP, secretos financieros). Preferí `op run` para inyección efímera; si necesitás un valor de prod, hacelo bajo aprobación humana explícita y nunca lo persistas.
- Antes de pushear, verificá que no se filtraron secretos (revisá el diff y respetá el secret scanning); cualquier credencial expuesta se considera comprometida y debe rotarse.
