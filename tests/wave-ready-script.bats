#!/usr/bin/env bats

load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../lib/wave-ready.sh"
}

@test "final PR body references mission issues without closing them" {
  run grep -F 'all_issues="${all_issues}- #${issue_num}"' "$SCRIPT"
  assert_success

  run grep -F 'all_issues="${all_issues}- Closes #${issue_num}"' "$SCRIPT"
  assert_failure

  run grep -F 'Issues are closed/reconciled by wave automation as each wave completes.' "$SCRIPT"
  assert_success
}

@test "already-merged wave path reconciles completed issues" {
  run grep -F 'find_merged_wave_pr_json "$MISSION_BRANCH" "$CONSOLIDATED_BRANCH"' "$SCRIPT"
  assert_success

  run grep -F 'reconcile_wave_issues "$CONFIG" "$WAVE" "$MERGED_WAVE_PR_NUMBER" "$MERGED_WAVE_PR_URL"' "$SCRIPT"
  assert_success

  run grep -F 'gh_auth issue close "$issue_num"' "$SCRIPT"
  assert_success

  run grep -F 'for label in status:ready status:in-progress status:blocked status:failed status:spec-invalid needs-human; do' "$SCRIPT"
  assert_success
}

@test "gate-closed wave path cleans labels from already closed issues" {
  run grep -F 'cleanup_closed_wave_issue_labels "$CONFIG" "$WAVE"' "$SCRIPT"
  assert_success

  run grep -F 'if [ "$state" = "CLOSED" ]; then' "$SCRIPT"
  assert_success

  run grep -F 'remove_transient_issue_labels "$issue_num"' "$SCRIPT"
  assert_success
}

@test "already-merged wave path closes resolved gate issues by default" {
  run grep -F ".cleanup.closeResolvedGateIssues // true" "$SCRIPT"
  assert_success

  run grep -F 'close_resolved_gate_issue "$CONFIG" "$WAVE" "✅ **Wave $WAVE reconciled.' "$SCRIPT"
  assert_success

  run grep -F 'gh_auth issue close "$gate_issue" --reason completed' "$SCRIPT"
  assert_success
}
