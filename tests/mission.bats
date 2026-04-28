#!/usr/bin/env bats

load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

setup() {
  source "$BATS_TEST_DIRNAME/../lib/mission.sh"
  MISSIONS_DIR="$BATS_TEST_DIRNAME/fixtures/missions"
}

# ─── mission_list_active ───

@test "mission_list_active returns only active missions" {
  run mission_list_active "$MISSIONS_DIR"
  assert_success
  assert_output --partial "cobros-export"
  assert_output --partial "cobros-reconciliation"
  refute_output --partial "paused-mission"
}

@test "mission_list_active returns empty for nonexistent directory" {
  run mission_list_active "/tmp/does-not-exist-$$"
  assert_success
  assert_output ""
}

@test "mission_list_effective_active_configs prefers mission branch config over stale default branch" {
  local tmpdir origin work config_path
  tmpdir=$(mktemp -d)
  origin="$tmpdir/origin.git"
  work="$tmpdir/work"

  git init --bare "$origin" >/dev/null
  git init -b main "$work" >/dev/null
  git -C "$work" config user.email "test@example.com"
  git -C "$work" config user.name "Test User"
  git -C "$work" remote add origin "$origin"

  mkdir -p "$work/.github/missions"
  cat > "$work/.github/missions/estado-de-cuenta.json" <<'JSON'
{"version":"5.0.0","mission":{"id":"estado-de-cuenta","baseBranch":"main","missionBranch":"mission/estado-de-cuenta","status":"active"},"waves":{"0":{"issues":[55],"gate":"human"}}}
JSON
  git -C "$work" add .github/missions/estado-de-cuenta.json
  git -C "$work" commit -m "main stale config" >/dev/null
  git -C "$work" push -u origin main >/dev/null 2>&1

  git -C "$work" checkout -b mission/estado-de-cuenta >/dev/null 2>&1
  cat > "$work/.github/missions/estado-de-cuenta.json" <<'JSON'
{"version":"5.0.0","mission":{"id":"estado-de-cuenta","baseBranch":"main","missionBranch":"mission/estado-de-cuenta","status":"active"},"waves":{"0":{"issues":[55],"gate":"human"},"4":{"issues":[77,81],"gate":"verify-then-auto"}}}
JSON
  git -C "$work" commit -am "mission branch config" >/dev/null
  git -C "$work" push -u origin mission/estado-de-cuenta >/dev/null 2>&1

  git -C "$work" checkout main >/dev/null 2>&1
  cd "$work"

  MISSION_EFFECTIVE_CONFIG_DIR="$tmpdir/effective" run mission_list_effective_active_configs ".github/missions"
  assert_success
  [ "${#lines[@]}" -eq 1 ]
  config_path="${lines[0]}"
  jq -e '.waves."4".issues | index(81)' "$config_path" >/dev/null
  [ "$(git -C "$work" rev-parse --is-shallow-repository)" = "false" ]

  rm -rf "$tmpdir"
}

# ─── mission_list_all ───

@test "mission_list_all returns all missions including paused" {
  run mission_list_all "$MISSIONS_DIR"
  assert_success
  assert_output --partial "cobros-export"
  assert_output --partial "cobros-reconciliation"
  assert_output --partial "paused-mission"
}

# ─── mission_config_path ───

@test "mission_config_path returns correct path" {
  run mission_config_path "$MISSIONS_DIR" "cobros-export"
  assert_success
  assert_output "$MISSIONS_DIR/cobros-export.json"
}

# ─── mission_find_for_issue ───

@test "mission_find_for_issue finds mission for issue in first mission" {
  run mission_find_for_issue "$MISSIONS_DIR" 101
  assert_success
  assert_output "cobros-export"
}

@test "mission_find_for_issue finds mission for issue in second mission" {
  run mission_find_for_issue "$MISSIONS_DIR" 204
  assert_success
  assert_output "cobros-reconciliation"
}

@test "mission_find_for_issue returns empty for unknown issue" {
  run mission_find_for_issue "$MISSIONS_DIR" 999
  assert_success
  assert_output ""
}

@test "mission_find_for_issue skips paused missions" {
  run mission_find_for_issue "$MISSIONS_DIR" 301
  assert_success
  assert_output ""
}

# ─── mission_get_status ───

@test "mission_get_status returns active" {
  run mission_get_status "$MISSIONS_DIR" "cobros-export"
  assert_success
  assert_output "active"
}

@test "mission_get_status returns paused" {
  run mission_get_status "$MISSIONS_DIR" "paused-mission"
  assert_success
  assert_output "paused"
}

# ─── mission_get_branch ───

@test "mission_get_branch returns mission branch" {
  run mission_get_branch "$MISSIONS_DIR" "cobros-export"
  assert_success
  assert_output "mission/cobros-export"
}

@test "mission_get_branch returns branch for second mission" {
  run mission_get_branch "$MISSIONS_DIR" "cobros-reconciliation"
  assert_success
  assert_output "mission/cobros-reconciliation"
}

# ─── mission_get_base_branch ───

@test "mission_get_base_branch returns main" {
  run mission_get_base_branch "$MISSIONS_DIR" "cobros-export"
  assert_success
  assert_output "main"
}

# ─── mission_get_id ───

@test "mission_get_id extracts id from config file" {
  local config="$MISSIONS_DIR/cobros-export.json"
  run mission_get_id "$config"
  assert_success
  assert_output "cobros-export"
}

# ─── mission_get_name ───

@test "mission_get_name extracts name from config file" {
  local config="$MISSIONS_DIR/cobros-export.json"
  run mission_get_name "$config"
  assert_success
  assert_output "Cobros — Exportación de PDFs"
}

# ─── mission_get_spec_source ───

@test "mission_get_spec_source extracts spec source" {
  local config="$MISSIONS_DIR/cobros-export.json"
  run mission_get_spec_source "$config"
  assert_success
  assert_output "mango-engineering/specs/mango-cobros/003-export"
}

@test "mission_get_spec_source returns empty when not set" {
  local config="$MISSIONS_DIR/paused-mission.json"
  run mission_get_spec_source "$config"
  assert_success
  assert_output ""
}

# ─── mission_validate ───

@test "mission_validate passes for valid config" {
  run mission_validate "$MISSIONS_DIR/cobros-export.json"
  assert_success
}

@test "mission_validate fails when mission.id is missing" {
  local tmpfile
  tmpfile=$(mktemp)
  echo '{"version":"5.0.0","mission":{"name":"bad"}}' > "$tmpfile"
  run mission_validate "$tmpfile"
  assert_failure
  assert_output --partial "mission.id"
  rm -f "$tmpfile"
}

@test "mission_validate fails when mission.baseBranch is missing" {
  local tmpfile
  tmpfile=$(mktemp)
  echo '{"version":"5.0.0","mission":{"id":"test","missionBranch":"mission/test","status":"active"}}' > "$tmpfile"
  run mission_validate "$tmpfile"
  assert_failure
  assert_output --partial "mission.baseBranch"
  rm -f "$tmpfile"
}

@test "mission_validate fails when mission.missionBranch is missing" {
  local tmpfile
  tmpfile=$(mktemp)
  echo '{"version":"5.0.0","mission":{"id":"test","baseBranch":"main","status":"active"}}' > "$tmpfile"
  run mission_validate "$tmpfile"
  assert_failure
  assert_output --partial "mission.missionBranch"
  rm -f "$tmpfile"
}

@test "mission_validate fails when mission.status is missing" {
  local tmpfile
  tmpfile=$(mktemp)
  echo '{"version":"5.0.0","mission":{"id":"test","baseBranch":"main","missionBranch":"mission/test"}}' > "$tmpfile"
  run mission_validate "$tmpfile"
  assert_failure
  assert_output --partial "mission.status"
  rm -f "$tmpfile"
}

@test "mission_validate fails when waves are missing" {
  local tmpfile
  tmpfile=$(mktemp)
  echo '{"version":"5.0.0","mission":{"id":"test","baseBranch":"main","missionBranch":"mission/test","status":"active"}}' > "$tmpfile"
  run mission_validate "$tmpfile"
  assert_failure
  assert_output --partial "waves"
  rm -f "$tmpfile"
}

# ─── mission_check_duplicate_issues ───

@test "mission_check_duplicate_issues passes when no duplicates" {
  run mission_check_duplicate_issues "$MISSIONS_DIR"
  assert_success
}

@test "mission_check_duplicate_issues detects duplicates" {
  local tmpdir
  tmpdir=$(mktemp -d)

  # Two missions claiming the same issue 101
  cat > "$tmpdir/mission-a.json" <<'EOF'
{"version":"5.0.0","mission":{"id":"a","baseBranch":"main","missionBranch":"mission/a","status":"active"},"waves":{"0":{"issues":[101,102],"gate":"human"}}}
EOF
  cat > "$tmpdir/mission-b.json" <<'EOF'
{"version":"5.0.0","mission":{"id":"b","baseBranch":"main","missionBranch":"mission/b","status":"active"},"waves":{"0":{"issues":[101,200],"gate":"human"}}}
EOF

  run mission_check_duplicate_issues "$tmpdir"
  assert_failure
  assert_output --partial "101"
  rm -rf "$tmpdir"
}
