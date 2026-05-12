#!/usr/bin/env bats

# Load bats helpers (CI sets BATS_LIB_PATH=/tmp; local uses brew paths)
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

# Load the library under test
setup() {
  source "$BATS_TEST_DIRNAME/../lib/roles.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ─── roles_enabled ───

@test "roles_enabled returns 0 when agentRoles.enabled is true" {
  run roles_enabled "$FIXTURES/config-v4-roles.json"
  assert_success
}

@test "roles_enabled returns 1 when agentRoles is absent" {
  run roles_enabled "$FIXTURES/config-v4-minimal.json"
  assert_failure
}

# ─── roles_get_pipeline ───

@test "roles_get_pipeline returns ordered roles" {
  run roles_get_pipeline "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_line --index 0 "architect"
  assert_line --index 1 "implement"
  assert_line --index 2 "qa"
}

@test "roles_get_pipeline returns empty for config without roles" {
  run roles_get_pipeline "$FIXTURES/config-v4-minimal.json"
  assert_success
  assert_output ""
}

@test "roles_get_pipeline returns partial pipeline" {
  run roles_get_pipeline "$FIXTURES/config-v4-roles-partial.json"
  assert_success
  assert_line --index 0 "implement"
  assert_line --index 1 "qa"
}

# ─── roles_get_prompt ───

@test "roles_get_prompt returns prompt path for architect" {
  run roles_get_prompt "$FIXTURES/config-v4-roles.json" "architect"
  assert_success
  assert_output ".github/prompts/architect.md"
}

@test "roles_get_prompt returns prompt path for qa" {
  run roles_get_prompt "$FIXTURES/config-v4-roles.json" "qa"
  assert_success
  assert_output ".github/prompts/qa-review.md"
}

@test "roles_get_prompt returns empty for nonexistent role" {
  run roles_get_prompt "$FIXTURES/config-v4-roles.json" "dba"
  assert_success
  assert_output ""
}

# ─── roles_get_output ───

@test "roles_get_output returns comment for architect" {
  run roles_get_output "$FIXTURES/config-v4-roles.json" "architect"
  assert_success
  assert_output "comment"
}

@test "roles_get_output returns pr for implement" {
  run roles_get_output "$FIXTURES/config-v4-roles.json" "implement"
  assert_success
  assert_output "pr"
}

@test "roles_get_output returns review for qa" {
  run roles_get_output "$FIXTURES/config-v4-roles.json" "qa"
  assert_success
  assert_output "review"
}

@test "roles_get_output defaults to comment for unknown role" {
  run roles_get_output "$FIXTURES/config-v4-minimal.json" "anything"
  assert_success
  assert_output "comment"
}

# ─── roles_is_required ───

@test "roles_is_required returns 0 for required role" {
  run roles_is_required "$FIXTURES/config-v4-roles.json" "architect"
  assert_success
}

@test "roles_is_required returns 1 for optional role" {
  run roles_is_required "$FIXTURES/config-v4-roles-partial.json" "qa"
  assert_failure
}

# ─── roles_has_role ───

@test "roles_has_role returns 0 for existing role" {
  run roles_has_role "$FIXTURES/config-v4-roles.json" "architect"
  assert_success
}

@test "roles_has_role returns 1 for missing role" {
  run roles_has_role "$FIXTURES/config-v4-roles.json" "dba"
  assert_failure
}

# ─── roles_next ───

@test "roles_next returns implement after architect" {
  run roles_next "$FIXTURES/config-v4-roles.json" "architect"
  assert_success
  assert_output "implement"
}

@test "roles_next returns qa after implement" {
  run roles_next "$FIXTURES/config-v4-roles.json" "implement"
  assert_success
  assert_output "qa"
}

@test "roles_next returns empty after last role" {
  run roles_next "$FIXTURES/config-v4-roles.json" "qa"
  assert_success
  assert_output ""
}

# ─── roles_first / roles_last ───

@test "roles_first returns architect" {
  run roles_first "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_output "architect"
}

@test "roles_last returns qa" {
  run roles_last "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_output "qa"
}

@test "roles_first returns empty for config without roles" {
  run roles_first "$FIXTURES/config-v4-minimal.json"
  assert_success
  assert_output ""
}

# ─── roles_count ───

@test "roles_count returns 3 for full pipeline" {
  run roles_count "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_output "3"
}

@test "roles_count returns 2 for partial pipeline" {
  run roles_count "$FIXTURES/config-v4-roles-partial.json"
  assert_success
  assert_output "2"
}

@test "roles_count returns 0 for config without roles" {
  run roles_count "$FIXTURES/config-v4-minimal.json"
  assert_success
  assert_output "0"
}

# ─── roles_current_for_issue ───

@test "roles_current_for_issue returns role from label" {
  run roles_current_for_issue '["status:ready", "role:implement"]' "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_output "implement"
}

@test "roles_current_for_issue returns first role when no role label" {
  run roles_current_for_issue '["status:ready"]' "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_output "architect"
}

# ─── roles_label ───

@test "roles_label generates correct label" {
  run roles_label "architect"
  assert_success
  assert_output "role:architect"
}

# ─── roles_all_labels ───

@test "roles_all_labels returns all role labels" {
  run roles_all_labels "$FIXTURES/config-v4-roles.json"
  assert_success
  assert_line --index 0 "role:architect"
  assert_line --index 1 "role:implement"
  assert_line --index 2 "role:qa"
}
