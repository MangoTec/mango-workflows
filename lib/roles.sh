#!/usr/bin/env bash
# Shell library for agent role management (v4.1)
# Source this file: source lib/roles.sh
#
# Agent roles define a pipeline of semantic gates:
#   architect → implement → qa
# Each role has a prompt template, output type, and required/optional flag.

set -euo pipefail

# Check if agent roles are enabled in config
# Usage: roles_enabled CONFIG_FILE
# Exit: 0 if enabled, 1 if not
roles_enabled() {
  local config="$1"
  local enabled
  enabled=$(jq -r '.agentRoles.enabled // false' "$config")
  [ "$enabled" = "true" ]
}

# Get the ordered pipeline of roles
# Usage: roles_get_pipeline CONFIG_FILE
# Output: space-separated role names in execution order
roles_get_pipeline() {
  local config="$1"
  jq -r '(.agentRoles.pipeline // []) | .[]' "$config"
}

# Get the prompt path for a role
# Usage: roles_get_prompt CONFIG_FILE ROLE_NAME
# Output: prompt file path (relative to repo root)
roles_get_prompt() {
  local config="$1" role="$2"
  jq -r ".agentRoles.roles[\"$role\"].prompt // empty" "$config"
}

# Get the output type for a role
# Usage: roles_get_output CONFIG_FILE ROLE_NAME
# Output: "comment" | "pr" | "review"
roles_get_output() {
  local config="$1" role="$2"
  jq -r ".agentRoles.roles[\"$role\"].output // \"comment\"" "$config"
}

# Check if a role is required (blocking gate)
# Usage: roles_is_required CONFIG_FILE ROLE_NAME
# Exit: 0 if required, 1 if optional
roles_is_required() {
  local config="$1" role="$2"
  local required
  # Note: jq's // treats false as falsy, so we use if/then/else to preserve false
  required=$(jq -r "if .agentRoles.roles[\"$role\"].required == false then \"false\" else \"true\" end" "$config")
  if [ "$required" = "true" ]; then
    return 0
  else
    return 1
  fi
}

# Check if a specific role exists in the config
# Usage: roles_has_role CONFIG_FILE ROLE_NAME
# Exit: 0 if exists, 1 if not
roles_has_role() {
  local config="$1" role="$2"
  jq -e ".agentRoles.roles[\"$role\"]" "$config" > /dev/null 2>&1
}

# Get the next role in the pipeline after a given role
# Usage: roles_next CONFIG_FILE CURRENT_ROLE
# Output: next role name, or empty if current is last
roles_next() {
  local config="$1" current="$2"
  local found_current=false

  while IFS= read -r role; do
    if [ "$found_current" = "true" ]; then
      echo "$role"
      return 0
    fi
    if [ "$role" = "$current" ]; then
      found_current=true
    fi
  done < <(roles_get_pipeline "$config")

  # Current was the last role or not found
  return 0
}

# Get the first role in the pipeline
# Usage: roles_first CONFIG_FILE
# Output: first role name
roles_first() {
  local config="$1"
  jq -r '(.agentRoles.pipeline // [])[0] // empty' "$config"
}

# Get the last role in the pipeline
# Usage: roles_last CONFIG_FILE
# Output: last role name
roles_last() {
  local config="$1"
  jq -r '(.agentRoles.pipeline // [])[-1] // empty' "$config"
}

# Count roles in the pipeline
# Usage: roles_count CONFIG_FILE
# Output: number of roles
roles_count() {
  local config="$1"
  jq -r '(.agentRoles.pipeline // []) | length' "$config"
}

# Determine which role should handle an issue based on its labels
# Usage: roles_current_for_issue LABELS_JSON CONFIG_FILE
# LABELS_JSON: JSON array string of label names, e.g. '["status:ready","role:architect"]'
# Output: current role name based on role:* label, or first role if none set
roles_current_for_issue() {
  local labels_json="$1" config="$2"

  # Look for a role:* label
  local role_label
  role_label=$(echo "$labels_json" | jq -r '[.[] | select(startswith("role:"))] | first // empty' 2>/dev/null)

  if [ -n "$role_label" ]; then
    echo "${role_label#role:}"
  else
    roles_first "$config"
  fi
}

# Generate the label for a role phase
# Usage: roles_label ROLE_NAME
# Output: "role:architect", "role:implement", etc.
roles_label() {
  local role="$1"
  echo "role:$role"
}

# Get all role labels (for cleanup)
# Usage: roles_all_labels CONFIG_FILE
# Output: space-separated role labels
roles_all_labels() {
  local config="$1"
  local role
  while IFS= read -r role; do
    [ -n "$role" ] && echo "role:$role"
  done < <(roles_get_pipeline "$config")
}
