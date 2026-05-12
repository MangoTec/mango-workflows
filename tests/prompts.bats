#!/usr/bin/env bats

# Load bats helpers (CI sets BATS_LIB_PATH=/tmp; local uses brew paths)
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

# Load the library under test
setup() {
  source "$BATS_TEST_DIRNAME/../lib/prompts.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  WORKFLOWS_ROOT="$BATS_TEST_DIRNAME/.."

  # Create a temp repo root with AGENTS.md
  REPO_ROOT=$(mktemp -d)
  echo "# Test Repo AGENTS.md" > "$REPO_ROOT/AGENTS.md"
  echo "Architecture: Service-Repository" >> "$REPO_ROOT/AGENTS.md"

  # Create repo-local prompt override
  mkdir -p "$REPO_ROOT/.github/prompts"
  echo "# Custom architect prompt for {{ROLE}}" > "$REPO_ROOT/.github/prompts/architect.md"
  echo "Issue: {{ISSUE_BODY}}" >> "$REPO_ROOT/.github/prompts/architect.md"
}

teardown() {
  [ -d "$REPO_ROOT" ] && rm -rf "$REPO_ROOT"
}

# ─── prompt_resolve_path ───

@test "prompt_resolve_path uses repo-local override when present" {
  run prompt_resolve_path "$FIXTURES/config-v4-roles.json" "architect" "$REPO_ROOT" "$WORKFLOWS_ROOT"
  assert_success
  assert_output "$REPO_ROOT/.github/prompts/architect.md"
}

@test "prompt_resolve_path falls back to shared template" {
  run prompt_resolve_path "$FIXTURES/config-v4-roles.json" "implement" "$REPO_ROOT" "$WORKFLOWS_ROOT"
  assert_success
  assert_output "$WORKFLOWS_ROOT/prompts/implement.md"
}

@test "prompt_resolve_path fails for nonexistent role" {
  run prompt_resolve_path "$FIXTURES/config-v4-roles.json" "dba" "$REPO_ROOT" "$WORKFLOWS_ROOT"
  assert_failure
}

# ─── prompt_read_agents_md ───

@test "prompt_read_agents_md returns contents when AGENTS.md exists" {
  run prompt_read_agents_md "$REPO_ROOT"
  assert_success
  assert_output --partial "Service-Repository"
}

@test "prompt_read_agents_md returns empty when no AGENTS.md" {
  local empty_dir
  empty_dir=$(mktemp -d)
  run prompt_read_agents_md "$empty_dir"
  assert_success
  assert_output ""
  rm -rf "$empty_dir"
}

# ─── prompt_exists ───

@test "prompt_exists returns 0 for architect with local override" {
  run prompt_exists "$FIXTURES/config-v4-roles.json" "architect" "$REPO_ROOT" "$WORKFLOWS_ROOT"
  assert_success
}

@test "prompt_exists returns 0 for implement with shared template" {
  run prompt_exists "$FIXTURES/config-v4-roles.json" "implement" "$REPO_ROOT" "$WORKFLOWS_ROOT"
  assert_success
}

@test "prompt_exists returns 1 for unknown role" {
  run prompt_exists "$FIXTURES/config-v4-roles.json" "dba" "$REPO_ROOT" "$WORKFLOWS_ROOT"
  assert_failure
}

# ─── prompt_build ───

@test "prompt_build substitutes ISSUE_BODY placeholder" {
  run prompt_build "$FIXTURES/config-v4-roles.json" "architect" "$REPO_ROOT" "$WORKFLOWS_ROOT" "Add payment endpoint"
  assert_success
  assert_output --partial "Add payment endpoint"
}

@test "prompt_build substitutes ROLE placeholder" {
  run prompt_build "$FIXTURES/config-v4-roles.json" "architect" "$REPO_ROOT" "$WORKFLOWS_ROOT" "Test issue"
  assert_success
  assert_output --partial "architect"
}

@test "prompt_build includes AGENTS_MD content" {
  # Use shared template (implement.md) which has {{AGENTS_MD}}
  run prompt_build "$FIXTURES/config-v4-roles.json" "implement" "$REPO_ROOT" "$WORKFLOWS_ROOT" "Test issue" "architect plan here"
  assert_success
  assert_output --partial "Service-Repository"
}

@test "prompt_build includes PREV_OUTPUT when provided" {
  run prompt_build "$FIXTURES/config-v4-roles.json" "implement" "$REPO_ROOT" "$WORKFLOWS_ROOT" "Test issue" "The architect says do X"
  assert_success
  assert_output --partial "The architect says do X"
}

@test "prompt_build handles missing PREV_OUTPUT gracefully" {
  run prompt_build "$FIXTURES/config-v4-roles.json" "implement" "$REPO_ROOT" "$WORKFLOWS_ROOT" "Test issue"
  assert_success
  assert_output --partial "No previous role output available"
}

@test "prompt_build fails for nonexistent role" {
  run prompt_build "$FIXTURES/config-v4-roles.json" "dba" "$REPO_ROOT" "$WORKFLOWS_ROOT" "Test issue"
  assert_failure
  assert_output --partial "ERROR"
}
