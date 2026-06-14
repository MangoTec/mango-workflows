---
description: Database schema rules and financial data precision for MySQL 8
globs: database/migrations/**/*.php, app/Models/**/*.php, app/Services/**/*.php, app/Repositories/**/*.php
---

- Money columns: DECIMAL(14,2) — never use FLOAT or DOUBLE
- Cast money fields in models: `protected $casts = ['amount' => 'decimal:2'];`
- IDs: BIGINT UNSIGNED with auto-increment
- Timestamps: created_at, updated_at on every table
- Soft deletes where business requires audit trail
- Foreign keys: RESTRICT for financial refs, CASCADE for child records
- Index frequently filtered columns (status, supplier_id, customer_id, created_at, rfc, clabe)
- Use `lockForUpdate()` when fetching records that will be modified to prevent race conditions
- Wrap multi-table operations in `DB::transaction(function () { ... })`
- Migration safety: never drop columns with data in production without explicit confirmation
- No hidden logic in Eloquent Observers for critical business operations — keep in Service layer
- Enforce eager loading with `->with()` in queries returning lists
