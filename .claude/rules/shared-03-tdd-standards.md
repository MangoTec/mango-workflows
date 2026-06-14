---
description: Test-driven development requirements for all Mango repositories
globs: "**"
---

# TDD Standards

## Mandatory testing

- New features MUST include corresponding tests
- Bug fixes MUST include a regression test that would have caught the bug
- Write test before or alongside implementation — never defer testing

## What MUST have tests

| Change Type | Required Test |
|---|---|
| New service method | Unit test |
| New API endpoint | Feature/integration test |
| New webhook handler | Feature test with realistic payload |
| New UI page/flow | E2E test (happy path) |
| Bug fix | Regression test |
| Financial operations | Edge case tests (zero amounts, max limits) |

## Quality rules

- Descriptive test names: `test_payment_creation_fails_when_credit_limit_exceeded`
- One assertion concept per test — avoid kitchen-sink tests
- Mock external APIs — never make real HTTP requests in tests
- Mock filesystem for file operations
- Mock queues for async job testing
- English for all test code (descriptions, variables, comments)
