---
name: security-audit
description: Perform a comprehensive security audit on a web application before deployment. Covers OWASP Top 10, authentication, authorization, input validation, secrets management, headers, CORS, and dependency vulnerabilities. Use when asked to "check security", "audit before publishing", "review for vulnerabilities", or "is this safe to deploy".
---

# Security Audit

Comprehensive security review for web applications. Covers the most critical vulnerability categories and produces an actionable report.

## Invoke This Skill When

- User asks to "audit security" or "check if my app is secure"
- User wants to verify an app is safe to publish/deploy
- User mentions OWASP, vulnerabilities, or penetration testing
- User asks "is this ready for production?" (security angle)
- Before deploying a new application or major feature

## Phase 1: Reconnaissance

Understand the application before auditing:

| Question | Why It Matters |
|----------|---------------|
| What framework/stack? | Determines attack surface and built-in protections |
| Does it handle auth? | Auth flaws are #1 vulnerability |
| Does it accept user input? | Input = injection surface |
| Does it store sensitive data? | Data exposure risk |
| Does it call external APIs? | SSRF, credential leakage |
| Is it an API, SPA, SSR, or hybrid? | Different threat models |

**Actions:**
1. Read `package.json`, `composer.json`, `requirements.txt`, or equivalent for dependencies
2. Identify the entry points (routes, controllers, endpoints)
3. Map the authentication and authorization flow
4. Identify where user input enters the system

## Phase 2: OWASP Top 10 Checklist

Systematically check each category:

### A01: Broken Access Control

| Check | What to Look For |
|-------|-----------------|
| Route protection | Are all sensitive routes behind auth middleware? |
| Authorization checks | Does the app verify the user can access *this specific resource*? (not just "is logged in") |
| IDOR | Can user A access user B's data by changing an ID in the URL/request? |
| Privilege escalation | Can a regular user access admin endpoints? |
| CORS misconfiguration | Is `Access-Control-Allow-Origin: *` used with credentials? |
| Directory traversal | Can path parameters escape intended directories? |

**Red flags:** Missing middleware on routes, raw IDs in URLs without ownership check, `role` stored client-side.

### A02: Cryptographic Failures

| Check | What to Look For |
|-------|-----------------|
| HTTPS enforcement | Is HTTP → HTTPS redirect configured? HSTS header present? |
| Password hashing | bcrypt/argon2/scrypt with appropriate cost? Never MD5/SHA1 for passwords |
| Sensitive data in transit | Are API keys, tokens, PII sent over unencrypted channels? |
| Secrets in code | Hardcoded API keys, passwords, tokens in source? |
| Weak JWT | Is the secret strong? Is algorithm pinned (no `alg: none`)? |

**Red flags:** `secret: "password123"`, MD5 anywhere near auth, `.env` committed to git, JWT without expiry.

### A03: Injection

| Check | What to Look For |
|-------|-----------------|
| SQL Injection | Raw string concatenation in queries? Use ORM/prepared statements? |
| NoSQL Injection | Unvalidated objects passed to MongoDB queries? |
| XSS (Reflected/Stored) | User input rendered without escaping? `dangerouslySetInnerHTML`? |
| Command Injection | User input in `exec()`, `system()`, `child_process`? |
| Template Injection | User input in template strings server-side? |
| Header Injection | User input in HTTP headers (CRLF injection)? |

**Red flags:** String interpolation in SQL, `innerHTML` with user data, `eval()` with user input.

### A04: Insecure Design

| Check | What to Look For |
|-------|-----------------|
| Rate limiting | Are login, registration, password reset rate-limited? |
| Business logic flaws | Can prices/amounts be manipulated client-side? |
| Missing validation | Are critical operations validated server-side (not just client)? |
| Enumeration | Do error messages reveal if user/email exists? |

**Red flags:** Client-side-only validation for financial operations, no rate limiting on auth endpoints.

### A05: Security Misconfiguration

| Check | What to Look For |
|-------|-----------------|
| Default credentials | Are default admin accounts removed? |
| Error exposure | Do production errors show stack traces, SQL queries, file paths? |
| Unnecessary features | Debug mode enabled? Unused endpoints exposed? |
| Security headers | CSP, X-Frame-Options, X-Content-Type-Options present? |
| Directory listing | Can users browse server directories? |

**Red flags:** `DEBUG=true` in production, verbose error responses with internals, missing security headers.

### A06: Vulnerable Dependencies

| Check | What to Look For |
|-------|-----------------|
| Known CVEs | Run `npm audit`, `composer audit`, `pip audit`, or `snyk test` |
| Outdated packages | Are critical packages (framework, auth, crypto) up to date? |
| Abandoned packages | Are dependencies still maintained? |

**Action:** Run the appropriate audit command and report critical/high vulnerabilities.

### A07: Authentication Failures

| Check | What to Look For |
|-------|-----------------|
| Brute force protection | Account lockout or exponential backoff after failed attempts? |
| Session management | Secure, HttpOnly, SameSite cookies? Session invalidation on logout? |
| Password policy | Minimum length enforced? Common password list checked? |
| MFA available | For sensitive operations, is 2FA supported/enforced? |
| Token storage | Are JWTs/tokens stored in httpOnly cookies (not localStorage)? |

**Red flags:** Tokens in localStorage, no session expiry, passwords stored in plain text, no lockout.

### A08: Software and Data Integrity

| Check | What to Look For |
|-------|-----------------|
| CI/CD security | Are builds reproducible? Are dependencies pinned? |
| Webhook verification | Do incoming webhooks validate signatures/IP? |
| Deserialization | Is untrusted data deserialized without validation? |

### A09: Logging & Monitoring Failures

| Check | What to Look For |
|-------|-----------------|
| Auth events logged | Failed logins, password changes, privilege changes? |
| Sensitive data in logs | Are passwords, tokens, credit cards stripped from logs? |
| Alerting | Are critical security events (many failed logins, admin actions) alerted? |

### A10: Server-Side Request Forgery (SSRF)

| Check | What to Look For |
|-------|-----------------|
| URL parameters | Does the app fetch URLs provided by users? |
| Internal access | Can user-supplied URLs reach internal services (169.254.169.254, localhost)? |
| Redirect following | Does the app follow redirects from user-supplied URLs? |

## Phase 3: Environment & Deployment

| Check | What to Look For |
|-------|-----------------|
| `.env` in `.gitignore` | Secrets must never be committed |
| Environment variables | Are all secrets loaded from env, not hardcoded? |
| Production config | Is debug mode off? Are dev tools disabled? |
| HTTPS | Is TLS configured and enforced? |
| Firewall / network | Are admin panels restricted by IP or VPN? |
| Docker (if applicable) | Non-root user? Minimal base image? No secrets in Dockerfile? |

## Phase 4: Security Headers Check

Verify these headers are present in responses:

```
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY (or SAMEORIGIN)
Content-Security-Policy: default-src 'self'; ...
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
X-XSS-Protection: 0 (deprecated but set to 0 to avoid false positives)
```

## Phase 5: Framework-Specific Checks

### Next.js / React

- Server Actions validate input with Zod/schema before processing
- API routes check authentication
- No secrets in client-side code (`NEXT_PUBLIC_` prefix = public)
- `middleware.ts` protects authenticated routes
- CSP configured in `next.config.js`

### Laravel / PHP

- CSRF token on all state-changing forms
- Mass assignment protection (`$fillable` / `$guarded`)
- Eloquent used (not raw SQL) or prepared statements
- `APP_DEBUG=false` in production
- Sanctum/Passport configured correctly
- File upload validation (type, size, extension)

### Express / Node.js

- `helmet` middleware for security headers
- Input validation (Joi, Zod, express-validator)
- Rate limiting (`express-rate-limit`)
- CORS configured restrictively (not `*`)
- No `eval()` or `Function()` with user input
- Parameterized queries (Prisma, Knex, or prepared statements)

### Python / FastAPI / Django

- CORS configured restrictively
- Input validation (Pydantic models)
- SQL injection prevention (ORM or parameterized queries)
- `SECRET_KEY` loaded from environment
- Debug mode disabled in production

## Phase 6: Report

Generate a structured report:

```markdown
# Security Audit Report

**Application:** [name]
**Stack:** [framework, language, database]
**Date:** [date]
**Auditor:** AI Security Audit Skill

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | X |
| 🟠 High | X |
| 🟡 Medium | X |
| 🔵 Low | X |
| ✅ Pass | X |

## Critical Findings

### [FINDING-01] [Title]
- **Severity:** Critical / High / Medium / Low
- **Category:** OWASP A0X
- **Location:** [file:line or endpoint]
- **Description:** [what's wrong]
- **Impact:** [what an attacker could do]
- **Remediation:** [specific fix with code example]
- **Priority:** Fix before deploy / Fix within 1 week / Improve later

## Passed Checks
- [list of things that are correctly implemented]

## Recommendations
- [prioritized list of improvements]
```

## Severity Classification

| Severity | Definition | Action |
|----------|-----------|--------|
| 🔴 Critical | Exploitable now, data breach or full compromise possible | **Block deploy** until fixed |
| 🟠 High | Significant vulnerability, exploitation requires some conditions | Fix before production or within 48h |
| 🟡 Medium | Real risk but limited impact or requires significant effort to exploit | Fix within 1-2 weeks |
| 🔵 Low | Minor issue, defense-in-depth improvement | Fix in next sprint |

## Quick Commands Reference

```bash
# JavaScript/Node.js
npm audit
npx better-npm-audit audit

# PHP/Composer
composer audit

# Python
pip audit
safety check

# General
npx is-website-vulnerable https://your-site.com
```

## Common Fixes (Quick Reference)

| Vulnerability | Fix |
|--------------|-----|
| XSS | Use framework's auto-escaping, CSP header, sanitize HTML input |
| SQL Injection | Use ORM or parameterized queries, never string concat |
| CSRF | Enable framework's CSRF protection, SameSite cookies |
| Exposed secrets | Move to env vars, rotate compromised secrets immediately |
| Missing auth | Add middleware to all sensitive routes, verify ownership |
| Weak sessions | httpOnly + Secure + SameSite cookies, short expiry, rotation |
| Open CORS | Whitelist specific origins, never `*` with credentials |
| Rate limiting | Add per-IP and per-user rate limits on auth/sensitive endpoints |
