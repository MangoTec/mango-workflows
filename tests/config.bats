#!/usr/bin/env bats

load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

setup() {
  source "$BATS_TEST_DIRNAME/../lib/config.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ─── cfg_primary_provider ───

@test "cfg_primary_provider returns 'copilot' from v4 config" {
  run cfg_primary_provider "$FIXTURES/config-v4.json"
  assert_success
  assert_output "copilot"
}

@test "cfg_primary_provider returns 'copilot' from v3 config" {
  run cfg_primary_provider "$FIXTURES/config-v3.json"
  assert_success
  assert_output "copilot"
}

@test "cfg_primary_provider returns 'codex' from v2 config (agent.provider fallback)" {
  run cfg_primary_provider "$FIXTURES/config-v2.json"
  assert_success
  assert_output "codex"
}

# ─── cfg_fallback_provider ───

@test "cfg_fallback_provider returns 'codex' from v4 config" {
  run cfg_fallback_provider "$FIXTURES/config-v4.json"
  assert_success
  assert_output "codex"
}

@test "cfg_fallback_provider returns empty when no fallback defined" {
  run cfg_fallback_provider "$FIXTURES/config-v2.json"
  assert_success
  assert_output ""
}

# ─── cfg_max_retries ───

@test "cfg_max_retries returns 2 from v4 config" {
  run cfg_max_retries "$FIXTURES/config-v4.json"
  assert_success
  assert_output "2"
}

@test "cfg_max_retries defaults to 2 when field missing" {
  run cfg_max_retries "$FIXTURES/config-v2.json"
  assert_success
  assert_output "2"
}

# ─── cfg_required_sections ───

@test "cfg_required_sections returns pipe-delimited string" {
  run cfg_required_sections "$FIXTURES/config-v4.json"
  assert_success
  assert_output "Requirements|Acceptance Criteria"
}

# ─── cfg_autonomy_level ───

@test "cfg_autonomy_level returns 'human-gate-pr' from v4 config" {
  run cfg_autonomy_level "$FIXTURES/config-v4.json"
  assert_success
  assert_output "human-gate-pr"
}

# ─── cfg_cleanup_flag ───

@test "cfg_cleanup_flag returns true for deleteMergedTaskBranches" {
  run cfg_cleanup_flag "$FIXTURES/config-v4.json" "deleteMergedTaskBranches"
  assert_success
  assert_output "true"
}

@test "cfg_cleanup_flag returns false for missing flag" {
  run cfg_cleanup_flag "$FIXTURES/config-v2.json" "deleteMergedTaskBranches"
  assert_success
  assert_output "false"
}

# ─── cfg_mission_id ───

@test "cfg_mission_id returns mission id from v4" {
  run cfg_mission_id "$FIXTURES/config-v4.json"
  assert_success
  assert_output "test-mission"
}

@test "cfg_mission_id returns empty for v3 config" {
  run cfg_mission_id "$FIXTURES/config-v3.json"
  assert_success
  assert_output ""
}
