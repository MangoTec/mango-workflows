#!/usr/bin/env bash
# Shell library for wave operations (v3/v4 compatible)
# Source this file: source lib/waves.sh

set -euo pipefail

# Detect if a wave value is a v4 object or v3 array
# Usage: wave_format_type CONFIG_FILE WAVE_NUM
# Output: "object" (v4) or "array" (v3)
wave_format_type() {
  local config="$1" wave="$2"
  jq -r ".waves[\"$wave\"] | type" "$config"
}

# Check if a wave exists in config
# Usage: wave_exists CONFIG_FILE WAVE_NUM
# Exit: 0 if exists, 1 if not
wave_exists() {
  local config="$1" wave="$2"
  jq -e ".waves[\"$wave\"]" "$config" > /dev/null 2>&1
}

# Get issue numbers for a wave (v3/v4 compatible)
# Usage: wave_get_issues CONFIG_FILE WAVE_NUM
# Output: space-separated issue numbers
wave_get_issues() {
  local config="$1" wave="$2"
  local fmt
  fmt=$(wave_format_type "$config" "$wave" 2>/dev/null || echo "null")

  if [ "$fmt" = "object" ]; then
    jq -r ".waves[\"$wave\"].issues[]" "$config" 2>/dev/null || true
  elif [ "$fmt" = "array" ]; then
    jq -r ".waves[\"$wave\"][]" "$config" 2>/dev/null || true
  fi
}

# Find which wave an issue belongs to
# Usage: wave_find_for_issue CONFIG_FILE ISSUE_NUM
# Output: wave number or empty string
wave_find_for_issue() {
  local config="$1" issue="$2"
  local wave fmt

  for wave in $(jq -r '.waves | keys[]' "$config"); do
    fmt=$(wave_format_type "$config" "$wave")
    if [ "$fmt" = "object" ]; then
      if jq -e ".waves[\"$wave\"].issues | index($issue)" "$config" > /dev/null 2>&1; then
        echo "$wave"
        return 0
      fi
    else
      if jq -e ".waves[\"$wave\"] | index($issue)" "$config" > /dev/null 2>&1; then
        echo "$wave"
        return 0
      fi
    fi
  done
  # Not found — return empty
  return 0
}

# Get gate type for a wave (v4 per-wave → v3 fallback → default)
# Usage: wave_get_gate_type CONFIG_FILE WAVE_NUM
# Output: "human" | "auto" | "verify-then-auto"
wave_get_gate_type() {
  local config="$1" wave="$2"
  local fmt gate_type wave_gate_required

  fmt=$(wave_format_type "$config" "$wave" 2>/dev/null || echo "null")

  # v4: per-wave gate config
  gate_type=""
  if [ "$fmt" = "object" ]; then
    gate_type=$(jq -r ".waves[\"$wave\"].gate // empty" "$config")
  fi

  # v3 fallback: autonomy.waveGateRequired
  if [ -z "$gate_type" ]; then
    wave_gate_required=$(jq -r '.autonomy.waveGateRequired // empty' "$config")
    if [ "$wave_gate_required" = "true" ]; then
      gate_type="human"
    elif [ "$wave_gate_required" = "false" ]; then
      gate_type="auto"
    fi
  fi

  # Default
  if [ -z "$gate_type" ]; then
    gate_type="human"
  fi

  echo "$gate_type"
}

# Get verification hook names for a wave
# Usage: wave_get_verify_hooks CONFIG_FILE WAVE_NUM
# Output: space-separated hook names or empty
wave_get_verify_hooks() {
  local config="$1" wave="$2"
  local fmt

  fmt=$(wave_format_type "$config" "$wave" 2>/dev/null || echo "null")

  if [ "$fmt" = "object" ]; then
    jq -r '(.waves["'"$wave"'"].verify // []) | .[]' "$config" 2>/dev/null || true
  fi
}
