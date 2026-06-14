---
description: Security standards for all Mango repositories (financial platform)
globs: "**"
---

# Security Standards

- Always validate and sanitize user input at system boundaries
- Never hardcode API keys or credentials — use environment variables via config
- Use prepared statements for database queries (ORMs handle this automatically)
- Log security-related events with context
- CORS, rate limiting, and CSRF protection on all public-facing endpoints
- Webhook endpoints MUST validate source identity (IP whitelist or shared secret)
- Financial amounts: DECIMAL(14,2) — NEVER use FLOAT for money
- Implement proper role-based access control on sensitive operations
- Strip sensitive fields (passwords, tokens, API keys) from logs
