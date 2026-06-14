---
description: Standards for consuming external REST APIs ensuring resilience, timeouts, and proper logging
globs: app/Services/**/*Api*.php, app/Services/**/*Client*.php, app/Jobs/**/*.php
---

- Wrap ALL external HTTP calls in try-catch with contextual logging
- Use Laravel HTTP client (Http::) — never raw cURL or manual Guzzle instantiation
- Set timeouts on every request: `->timeout(5)` minimum — external services can hang
- Retry transient failures: `->retry(3, 100)` for idempotent calls
- Evaluate responses: use `->successful()`, `->failed()`, or `->throw()`
- Never expose raw external API errors to clients — throw domain-specific exceptions
- Encapsulate all HTTP requests in dedicated Client Services — controllers/jobs must not call Http:: directly
- Load base URLs, API keys, and tokens from environment via `config()` — never hardcode
- Log critical failures with full context (request payload, response status, entity ID)
- Dispatch heavy or non-urgent external calls to background Jobs on the queue
- Strip sensitive fields (tokens, passwords) before logging request/response payloads
