#!/usr/bin/env bash
# Shell library for running verification hooks
# Source this file: source lib/verify.sh

set -euo pipefail

# Get the shell command for a named hook
# Usage: verify_get_hook_cmd CONFIG_FILE HOOK_NAME
# Output: command string or empty
verify_get_hook_cmd() {
  local config="$1" hook_name="$2"
  jq -r ".verification.hooks[\"$hook_name\"] // empty" "$config"
}

# Run all verification hooks for a wave
# Usage: verify_run_hooks CONFIG_FILE WAVE_NUM
# Output: pass/fail per hook to stdout; exit 0 if all pass, 1 if any fail
verify_run_hooks() {
  local config="$1" wave="$2"
  local hook_names hook_name hook_cmd hook_exit
  local all_passed=true

  # Get hook names from wave config
  hook_names=$(jq -r '(.waves["'"$wave"'"].verify // []) | .[]' "$config" 2>/dev/null || true)

  if [ -z "$hook_names" ]; then
    echo "No verification hooks for wave $wave"
    return 0
  fi

  for hook_name in $hook_names; do
    hook_cmd=$(verify_get_hook_cmd "$config" "$hook_name")
    if [ -z "$hook_cmd" ]; then
      echo "WARN: hook '$hook_name' not found in verification.hooks"
      continue
    fi

    set +e
    ( eval "$hook_cmd" ) > /dev/null 2>&1
    hook_exit=$?
    set -e

    if [ "$hook_exit" -ne 0 ]; then
      echo "FAIL: $hook_name (exit $hook_exit)"
      all_passed=false
    else
      echo "PASS: $hook_name"
    fi
  done

  if [ "$all_passed" = "true" ]; then
    return 0
  else
    return 1
  fi
}
