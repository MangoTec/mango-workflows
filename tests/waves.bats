#!/usr/bin/env bats

# Load bats helpers (CI sets BATS_LIB_PATH=/tmp; local uses brew paths)
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

# Load the library under test
setup() {
  source "$BATS_TEST_DIRNAME/../lib/waves.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ─── wave_get_issues ───

@test "wave_get_issues returns issues from v4 object format" {
  run wave_get_issues "$FIXTURES/config-v4.json" "1"
  assert_success
  assert_output --partial "42"
  assert_output --partial "43"
  assert_output --partial "44"
}

@test "wave_get_issues returns issues from v3 array format" {
  run wave_get_issues "$FIXTURES/config-v3.json" "0"
  assert_success
  assert_output --partial "20"
  assert_output --partial "21"
}

@test "wave_get_issues returns empty for nonexistent wave" {
  run wave_get_issues "$FIXTURES/config-v4.json" "99"
  assert_success
  assert_output ""
}

# ─── wave_find_for_issue ───

@test "wave_find_for_issue returns correct wave for v4 config" {
  run wave_find_for_issue "$FIXTURES/config-v4.json" 43
  assert_success
  assert_output "1"
}

@test "wave_find_for_issue returns correct wave for v3 config" {
  run wave_find_for_issue "$FIXTURES/config-v3.json" 25
  assert_success
  assert_output "2"
}

@test "wave_find_for_issue returns empty for issue not in any wave" {
  run wave_find_for_issue "$FIXTURES/config-v4.json" 999
  assert_success
  assert_output ""
}

# ─── wave_get_gate_type ───

@test "wave_get_gate_type returns 'human' for v4 wave with gate:human" {
  run wave_get_gate_type "$FIXTURES/config-v4.json" "2"
  assert_success
  assert_output "human"
}

@test "wave_get_gate_type returns 'verify-then-auto' for v4 wave" {
  run wave_get_gate_type "$FIXTURES/config-v4.json" "1"
  assert_success
  assert_output "verify-then-auto"
}

@test "wave_get_gate_type returns 'auto' for v4 wave with gate:auto" {
  run wave_get_gate_type "$FIXTURES/config-v4.json" "0"
  assert_success
  assert_output "auto"
}

@test "wave_get_gate_type falls back to 'human' when v3 waveGateRequired=true" {
  run wave_get_gate_type "$FIXTURES/config-v3.json" "0"
  assert_success
  assert_output "human"
}

@test "wave_get_gate_type falls back to 'auto' when v3 waveGateRequired=false" {
  run wave_get_gate_type "$FIXTURES/config-v4-minimal.json" "0"
  assert_success
  assert_output "auto"
}

@test "wave_get_gate_type defaults to 'human' when no gate config at all" {
  run wave_get_gate_type "$FIXTURES/config-v2.json" "0"
  assert_success
  assert_output "human"
}

# ─── wave_get_verify_hooks ───

@test "wave_get_verify_hooks returns hook names for v4 wave with verify array" {
  run wave_get_verify_hooks "$FIXTURES/config-v4.json" "1"
  assert_success
  assert_output --partial "verify:build"
  assert_output --partial "verify:types"
}

@test "wave_get_verify_hooks returns empty for wave without verify" {
  run wave_get_verify_hooks "$FIXTURES/config-v4.json" "0"
  assert_success
  assert_output ""
}

# ─── wave_exists ───

@test "wave_exists exits 0 for existing wave" {
  run wave_exists "$FIXTURES/config-v4.json" "1"
  assert_success
}

@test "wave_exists exits 1 for nonexistent wave" {
  run wave_exists "$FIXTURES/config-v4.json" "99"
  assert_failure
}

# ─── wave_format_type ───

@test "wave_format_type returns 'object' for v4 wave" {
  run wave_format_type "$FIXTURES/config-v4.json" "0"
  assert_success
  assert_output "object"
}

@test "wave_format_type returns 'array' for v3 wave" {
  run wave_format_type "$FIXTURES/config-v3.json" "0"
  assert_success
  assert_output "array"
}
