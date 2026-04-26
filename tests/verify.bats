#!/usr/bin/env bats

load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-support/load"
load "${BATS_LIB_PATH:-/opt/homebrew/lib}/bats-assert/load"

setup() {
  source "$BATS_TEST_DIRNAME/../lib/verify.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ─── verify_get_hook_cmd ───

@test "verify_get_hook_cmd returns command string for defined hook" {
  run verify_get_hook_cmd "$FIXTURES/config-v4.json" "verify:build"
  assert_success
  assert_output "npm run build 2>&1 | tail -20"
}

@test "verify_get_hook_cmd returns empty for undefined hook" {
  run verify_get_hook_cmd "$FIXTURES/config-v4.json" "verify:nonexistent"
  assert_success
  assert_output ""
}

# ─── verify_run_hooks (with fixture config that uses real commands) ───

@test "verify_run_hooks exits 0 when all hooks pass" {
  # Create a temp config with hooks that always succeed
  local tmp_config
  tmp_config=$(mktemp)
  cat > "$tmp_config" <<'EOF'
{
  "waves": {
    "0": {
      "issues": [1],
      "gate": "verify-then-auto",
      "verify": ["check:ok"]
    }
  },
  "verification": {
    "hooks": {
      "check:ok": "echo ok"
    }
  }
}
EOF
  run verify_run_hooks "$tmp_config" "0"
  assert_success
  assert_output --partial "PASS: check:ok"
  rm -f "$tmp_config"
}

@test "verify_run_hooks exits 1 when any hook fails" {
  local tmp_config
  tmp_config=$(mktemp)
  cat > "$tmp_config" <<'EOF'
{
  "waves": {
    "0": {
      "issues": [1],
      "gate": "verify-then-auto",
      "verify": ["check:fail"]
    }
  },
  "verification": {
    "hooks": {
      "check:fail": "exit 1"
    }
  }
}
EOF
  run verify_run_hooks "$tmp_config" "0"
  assert_failure
  assert_output --partial "FAIL: check:fail"
  rm -f "$tmp_config"
}

@test "verify_run_hooks skips missing hooks with warning" {
  local tmp_config
  tmp_config=$(mktemp)
  cat > "$tmp_config" <<'EOF'
{
  "waves": {
    "0": {
      "issues": [1],
      "gate": "verify-then-auto",
      "verify": ["nonexistent"]
    }
  },
  "verification": {
    "hooks": {}
  }
}
EOF
  run verify_run_hooks "$tmp_config" "0"
  assert_success
  assert_output --partial "WARN: hook 'nonexistent' not found"
  rm -f "$tmp_config"
}

@test "verify_run_hooks returns 0 when no hooks defined" {
  run verify_run_hooks "$FIXTURES/config-v4.json" "0"
  assert_success
  assert_output --partial "No verification hooks"
}
