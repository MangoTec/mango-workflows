#!/usr/bin/env bash
# Shell library for reading pipeline-config.json (v2/v3/v4 compatible)
# Source this file: source lib/config.sh

set -euo pipefail

# Primary AI provider (v4: agents.primary → v3: agents.primary → v2: agent.provider → default)
# Usage: cfg_primary_provider CONFIG_FILE
cfg_primary_provider() {
  local config="$1"
  local val
  val=$(jq -r '.agents.primary // .agent.primary // .agent.provider // "copilot"' "$config")
  echo "$val"
}

# Fallback AI provider
# Usage: cfg_fallback_provider CONFIG_FILE
cfg_fallback_provider() {
  local config="$1"
  jq -r '.agents.fallbackProvider // .agent.fallbackProvider // empty' "$config"
}

# Max retries
# Usage: cfg_max_retries CONFIG_FILE
cfg_max_retries() {
  local config="$1"
  jq -r '.autonomy.maxRetries // 2' "$config"
}

# Copilot username
# Usage: cfg_copilot_user CONFIG_FILE
cfg_copilot_user() {
  local config="$1"
  jq -r '.providers.copilot.username // .copilot.username // "copilot"' "$config"
}

# Spec linter: minimum body length
# Usage: cfg_spec_linter_min_body CONFIG_FILE
cfg_spec_linter_min_body() {
  local config="$1"
  jq -r '.specLinter.minBodyLength // 200' "$config"
}

# Spec linter: required sections (pipe-delimited)
# Usage: cfg_required_sections CONFIG_FILE
cfg_required_sections() {
  local config="$1"
  jq -r '(.specLinter.requiredSections // ["Requirements","Acceptance Criteria"]) | join("|")' "$config"
}

# Spec linter: validate file references
# Usage: cfg_validate_file_refs CONFIG_FILE
cfg_validate_file_refs() {
  local config="$1"
  jq -r '.specLinter.validateFileRefs // false' "$config"
}

# Spec linter: require spec source
# Usage: cfg_require_spec_source CONFIG_FILE
cfg_require_spec_source() {
  local config="$1"
  jq -r '.specLinter.requireSpecSource // false' "$config"
}

# Mission ID
# Usage: cfg_mission_id CONFIG_FILE
cfg_mission_id() {
  local config="$1"
  jq -r '.mission.id // empty' "$config"
}

# Spec source path
# Usage: cfg_spec_source CONFIG_FILE
cfg_spec_source() {
  local config="$1"
  jq -r '.mission.specSource // empty' "$config"
}

# Autonomy level
# Usage: cfg_autonomy_level CONFIG_FILE
cfg_autonomy_level() {
  local config="$1"
  jq -r '.autonomy.level // "human-gate-pr"' "$config"
}

# Cleanup flag
# Usage: cfg_cleanup_flag CONFIG_FILE FLAG_NAME
cfg_cleanup_flag() {
  local config="$1" flag="$2"
  jq -r ".cleanup.$flag // false" "$config"
}
