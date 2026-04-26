#!/usr/bin/env bash
# Shell library for multi-mission operations (v5)
# Missions live in .github/missions/{id}.json
# Source this file: source lib/mission.sh

set -euo pipefail

# List active mission IDs (status=active)
# Usage: mission_list_active MISSIONS_DIR
mission_list_active() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local status
    status=$(jq -r '.mission.status // "active"' "$f")
    if [ "$status" = "active" ]; then
      jq -r '.mission.id' "$f"
    fi
  done
}

# List all mission IDs regardless of status
# Usage: mission_list_all MISSIONS_DIR
mission_list_all() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    jq -r '.mission.id' "$f"
  done
}

# Get config file path for a mission
# Usage: mission_config_path MISSIONS_DIR MISSION_ID
mission_config_path() {
  local dir="$1" id="$2"
  echo "$dir/$id.json"
}

# Find which active mission owns an issue number
# Usage: mission_find_for_issue MISSIONS_DIR ISSUE_NUM
# Output: mission id or empty
mission_find_for_issue() {
  local dir="$1" issue="$2"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local status
    status=$(jq -r '.mission.status // "active"' "$f")
    if [ "$status" != "active" ]; then
      continue
    fi
    # Scan all waves for the issue
    local found
    found=$(jq -r --argjson issue "$issue" '
      [.waves | to_entries[] | .value.issues // [] | select(index($issue))] | length
    ' "$f")
    if [ "$found" -gt 0 ]; then
      jq -r '.mission.id' "$f"
      return 0
    fi
  done
  return 0
}

# Get mission status
# Usage: mission_get_status MISSIONS_DIR MISSION_ID
mission_get_status() {
  local dir="$1" id="$2"
  jq -r '.mission.status // "active"' "$dir/$id.json"
}

# Get mission branch (the branch agents PR against)
# Usage: mission_get_branch MISSIONS_DIR MISSION_ID
mission_get_branch() {
  local dir="$1" id="$2"
  jq -r '.mission.missionBranch' "$dir/$id.json"
}

# Get base branch (usually main)
# Usage: mission_get_base_branch MISSIONS_DIR MISSION_ID
mission_get_base_branch() {
  local dir="$1" id="$2"
  jq -r '.mission.baseBranch' "$dir/$id.json"
}

# Get mission id from a config file path
# Usage: mission_get_id CONFIG_FILE
mission_get_id() {
  local config="$1"
  jq -r '.mission.id' "$config"
}

# Get mission name from a config file path
# Usage: mission_get_name CONFIG_FILE
mission_get_name() {
  local config="$1"
  jq -r '.mission.name // empty' "$config"
}

# Get spec source from a config file path
# Usage: mission_get_spec_source CONFIG_FILE
mission_get_spec_source() {
  local config="$1"
  jq -r '.mission.specSource // empty' "$config"
}

# Validate a mission config file has required fields
# Usage: mission_validate CONFIG_FILE
# Exit: 0 if valid, 1 with error messages if not
mission_validate() {
  local config="$1"
  local errors=""

  local id
  id=$(jq -r '.mission.id // empty' "$config")
  if [ -z "$id" ]; then
    errors="${errors}Missing required field: mission.id\n"
  fi

  local base
  base=$(jq -r '.mission.baseBranch // empty' "$config")
  if [ -z "$base" ]; then
    errors="${errors}Missing required field: mission.baseBranch\n"
  fi

  local branch
  branch=$(jq -r '.mission.missionBranch // empty' "$config")
  if [ -z "$branch" ]; then
    errors="${errors}Missing required field: mission.missionBranch\n"
  fi

  local status
  status=$(jq -r '.mission.status // empty' "$config")
  if [ -z "$status" ]; then
    errors="${errors}Missing required field: mission.status\n"
  fi

  local has_waves
  has_waves=$(jq -r '.waves // empty | length' "$config" 2>/dev/null || echo "0")
  if [ "$has_waves" = "0" ] || [ -z "$has_waves" ]; then
    errors="${errors}Missing required field: waves\n"
  fi

  if [ -n "$errors" ]; then
    printf "%b" "$errors"
    return 1
  fi
  return 0
}

# Check for duplicate issues across active missions
# Usage: mission_check_duplicate_issues MISSIONS_DIR
# Exit: 0 if no duplicates, 1 with details if found
mission_check_duplicate_issues() {
  local dir="$1"
  local all_issues=""

  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local status
    status=$(jq -r '.mission.status // "active"' "$f")
    if [ "$status" != "active" ]; then
      continue
    fi
    local mid
    mid=$(jq -r '.mission.id' "$f")
    local issues
    issues=$(jq -r '[.waves | to_entries[] | .value.issues // [] | .[]] | .[]' "$f" 2>/dev/null || true)
    for iss in $issues; do
      all_issues="${all_issues}${iss} ${mid}\n"
    done
  done

  local duplicates
  duplicates=$(printf "%b" "$all_issues" | awk '{print $1}' | sort | uniq -d)
  if [ -n "$duplicates" ]; then
    echo "Duplicate issues found across missions:"
    for dup in $duplicates; do
      local owners
      owners=$(printf "%b" "$all_issues" | awk -v i="$dup" '$1 == i {print $2}' | tr '\n' ', ' | sed 's/,$//')
      echo "  Issue #$dup claimed by: $owners"
    done
    return 1
  fi
  return 0
}
