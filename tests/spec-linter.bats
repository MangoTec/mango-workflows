#!/usr/bin/env bats

load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

setup() {
  source "$BATS_TEST_DIRNAME/../lib/spec-linter.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ─── lint_body_length ───

@test "lint_body_length passes when body exceeds minimum" {
  BODY=$(printf '%0.s-' {1..300})
  run lint_body_length "$BODY" 200
  assert_success
  assert_output ""
}

@test "lint_body_length fails with error when body too short" {
  run lint_body_length "short body" 200
  assert_success
  assert_output --partial "Body too short"
  assert_output --partial "minimum: 200"
}

@test "lint_body_length handles empty body" {
  run lint_body_length "" 200
  assert_success
  assert_output --partial "Body too short (0 chars"
}

# ─── lint_required_sections ───

@test "lint_required_sections passes when all sections present" {
  BODY=$'## Requirements\nSome reqs\n## Acceptance Criteria\nSome criteria'
  run lint_required_sections "$BODY" "Requirements|Acceptance Criteria"
  assert_success
  assert_output ""
}

@test "lint_required_sections passes with ### heading variant" {
  BODY=$'### Requirements\nSome reqs\n### Acceptance Criteria\nSome criteria'
  run lint_required_sections "$BODY" "Requirements|Acceptance Criteria"
  assert_success
  assert_output ""
}

@test "lint_required_sections fails listing each missing section" {
  BODY=$'## Introduction\nSome text'
  run lint_required_sections "$BODY" "Requirements|Acceptance Criteria"
  assert_success
  assert_output --partial "Missing required section: Requirements"
  assert_output --partial "Missing required section: Acceptance Criteria"
}

@test "lint_required_sections is case-insensitive" {
  BODY=$'## requirements\nSome reqs\n## acceptance criteria\nSome criteria'
  run lint_required_sections "$BODY" "Requirements|Acceptance Criteria"
  assert_success
  assert_output ""
}

# ─── lint_file_refs ───

@test "lint_file_refs passes when all referenced files exist" {
  BODY='Check `lib/waves.sh` for details'
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  run lint_file_refs "$BODY" "$REPO_ROOT"
  assert_success
  assert_output ""
}

@test "lint_file_refs fails listing each missing file" {
  BODY='See `src/nonexistent.ts` and `api/fake.php` for details'
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  run lint_file_refs "$BODY" "$REPO_ROOT"
  assert_success
  assert_output --partial "Referenced file not found: src/nonexistent.ts"
  assert_output --partial "Referenced file not found: api/fake.php"
}

# ─── lint_spec_source ───

@test "lint_spec_source passes when body contains spec source string" {
  BODY="This implements specs/test-mission/spec.md requirements"
  run lint_spec_source "$BODY" "specs/test-mission/spec.md"
  assert_success
  assert_output ""
}

@test "lint_spec_source fails when spec source not mentioned" {
  BODY="This implements some random thing"
  run lint_spec_source "$BODY" "specs/test-mission/spec.md"
  assert_success
  assert_output --partial "Spec does not reference source-of-truth"
}

@test "lint_spec_source passes when spec source is empty" {
  run lint_spec_source "any body" ""
  assert_success
  assert_output ""
}
