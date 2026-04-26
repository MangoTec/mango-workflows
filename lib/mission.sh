#!/usr/bin/env bash
# Shell library for mission operations (v5 multi-mission + legacy v2/v3/v4)
# Missions live in .github/missions/{id}.json. Legacy repos keep
# .github/pipeline-config.json and are treated as a single "default" mission.
# Source this file: source lib/mission.sh

set -euo pipefail

# Get the legacy single-config path for a missions dir.
# Usage: mission_legacy_config_path MISSIONS_DIR
mission_legacy_config_path() {
  local dir="$1"
  local github_dir
  github_dir="$(cd "$(dirname "$dir")" 2>/dev/null && pwd || true)"
  if [ -n "$github_dir" ]; then
    echo "$github_dir/pipeline-config.json"
  else
    echo "$dir/../pipeline-config.json"
  fi
}

# Return true if .github/missions has at least one JSON mission file.
# Usage: mission_has_multi_config MISSIONS_DIR
mission_has_multi_config() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null | grep -q .
}

# List active mission config paths.
# Usage: mission_list_active_configs MISSIONS_DIR
mission_list_active_configs() {
  local dir="$1"
  local f status legacy

  if mission_has_multi_config "$dir"; then
    for f in "$dir"/*.json; do
      [ -f "$f" ] || continue
      status=$(jq -r '.mission.status // "active"' "$f")
      if [ "$status" = "active" ]; then
        echo "$f"
      fi
    done
    return 0
  fi

  legacy=$(mission_legacy_config_path "$dir")
  if [ -f "$legacy" ]; then
    status=$(jq -r '.mission.status // "active"' "$legacy")
    if [ "$status" = "active" ]; then
      echo "$legacy"
    fi
  fi
}

# List all mission config paths regardless of status.
# Usage: mission_list_all_configs MISSIONS_DIR
mission_list_all_configs() {
  local dir="$1"
  local f legacy

  if mission_has_multi_config "$dir"; then
    for f in "$dir"/*.json; do
      [ -f "$f" ] || continue
      echo "$f"
    done
    return 0
  fi

  legacy=$(mission_legacy_config_path "$dir")
  [ -f "$legacy" ] && echo "$legacy"
}

# Get mission id from a config file path. Legacy configs without mission.id
# are represented as "default" so workflows can still identify them.
# Usage: mission_get_id CONFIG_FILE
mission_get_id() {
  local config="$1"
  jq -r '.mission.id // "default"' "$config"
}

# List active mission IDs (status=active)
# Usage: mission_list_active MISSIONS_DIR
mission_list_active() {
  local dir="$1"
  local f
  for f in $(mission_list_active_configs "$dir"); do
    mission_get_id "$f"
  done
}

# List all mission IDs regardless of status
# Usage: mission_list_all MISSIONS_DIR
mission_list_all() {
  local dir="$1"
  local f
  for f in $(mission_list_all_configs "$dir"); do
    mission_get_id "$f"
  done
}

# Get config file path for a mission
# Usage: mission_config_path MISSIONS_DIR MISSION_ID
mission_config_path() {
  local dir="$1" id="$2"
  if [ "$id" = "default" ]; then
    mission_legacy_config_path "$dir"
  else
    echo "$dir/$id.json"
  fi
}

# Check whether a config owns an issue number.
# Usage: mission_config_has_issue CONFIG_FILE ISSUE_NUM
mission_config_has_issue() {
  local config="$1" issue="$2"
  jq -e --argjson issue "$issue" '
    [
      (.waves // {})
      | to_entries[]
      | (.value | if type == "object" then (.issues // []) else . end)
      | select(index($issue))
    ]
    | length > 0
  ' "$config" >/dev/null
}

# Find which active mission config owns an issue number.
# Usage: mission_find_config_for_issue MISSIONS_DIR ISSUE_NUM
# Output: config path or empty
mission_find_config_for_issue() {
  local dir="$1" issue="$2"
  local f
  for f in $(mission_list_active_configs "$dir"); do
    if mission_config_has_issue "$f" "$issue"; then
      echo "$f"
      return 0
    fi
  done
  return 0
}

# Find which active mission owns an issue number.
# Usage: mission_find_for_issue MISSIONS_DIR ISSUE_NUM
# Output: mission id or empty
mission_find_for_issue() {
  local dir="$1" issue="$2"
  local config
  config=$(mission_find_config_for_issue "$dir" "$issue")
  if [ -n "$config" ]; then
    mission_get_id "$config"
  fi
}

# Get mission status
# Usage: mission_get_status MISSIONS_DIR MISSION_ID
mission_get_status() {
  local dir="$1" id="$2"
  jq -r '.mission.status // "active"' "$(mission_config_path "$dir" "$id")"
}

# Get mission branch (the branch agents PR against)
# Usage: mission_get_branch MISSIONS_DIR MISSION_ID
mission_get_branch() {
  local dir="$1" id="$2"
  mission_get_branch_from_config "$(mission_config_path "$dir" "$id")"
}

# Get base branch (usually main)
# Usage: mission_get_base_branch MISSIONS_DIR MISSION_ID
mission_get_base_branch() {
  local dir="$1" id="$2"
  mission_get_base_branch_from_config "$(mission_config_path "$dir" "$id")"
}

# Get base branch from a config path.
# Usage: mission_get_base_branch_from_config CONFIG_FILE
mission_get_base_branch_from_config() {
  local config="$1"
  jq -r '.mission.baseBranch // "main"' "$config"
}

# Get mission branch from a config path.
# v5 mission files default to mission/{id}. Legacy single configs default to
# their base branch so existing PR-to-main flows continue to work.
# Usage: mission_get_branch_from_config CONFIG_FILE
mission_get_branch_from_config() {
  local config="$1"
  jq -r '
    if (.mission.missionBranch // "") != "" then
      .mission.missionBranch
    elif (.version // "" | startswith("5.")) and ((.mission.id // "") != "") then
      "mission/" + .mission.id
    else
      (.mission.baseBranch // "main")
    end
  ' "$config"
}

# Get mission name from a config file path
# Usage: mission_get_name CONFIG_FILE
mission_get_name() {
  local config="$1"
  jq -r '.mission.name // .mission.id // "Default pipeline"' "$config"
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
    issues=$(jq -r '
      [
        (.waves // {})
        | to_entries[]
        | (.value | if type == "object" then (.issues // []) else . end)
        | .[]
      ]
      | .[]
    ' "$f" 2>/dev/null || true)
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
