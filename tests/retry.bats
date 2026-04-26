#!/usr/bin/env bats

load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

setup() {
  source "$BATS_TEST_DIRNAME/../lib/retry.sh"
}

# ─── retry_count_from_labels ───

@test "retry_count_from_labels returns 0 when no retry labels" {
  run retry_count_from_labels '["status:ready", "wave:1"]'
  assert_success
  assert_output "0"
}

@test "retry_count_from_labels returns 2 when retry:1 and retry:2 present" {
  run retry_count_from_labels '["retry:1", "status:ready", "retry:2"]'
  assert_success
  assert_output "2"
}

@test "retry_count_from_labels ignores non-retry labels" {
  run retry_count_from_labels '["retry:1", "wave:0", "status:failed"]'
  assert_success
  assert_output "1"
}

# ─── retry_next_provider ───

@test "retry_next_provider returns fallback on odd retry" {
  run retry_next_provider 1 "copilot" "codex"
  assert_success
  assert_output "codex"
}

@test "retry_next_provider returns primary on even retry" {
  run retry_next_provider 2 "copilot" "codex"
  assert_success
  assert_output "copilot"
}

@test "retry_next_provider returns primary when no fallback defined" {
  run retry_next_provider 1 "copilot" ""
  assert_success
  assert_output "copilot"
}

# ─── retry_should_escalate ───

@test "retry_should_escalate exits 0 when retry exceeds max" {
  run retry_should_escalate 3 2
  assert_success
}

@test "retry_should_escalate exits 1 when retry within max" {
  run retry_should_escalate 2 2
  assert_failure
}
