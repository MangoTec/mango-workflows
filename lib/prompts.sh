#!/usr/bin/env bash
# Shell library for prompt template resolution (v4.1)
# Source this file: source lib/prompts.sh
#
# Resolves prompt templates for each agent role by combining:
# 1. Base template from mango-workflows/prompts/
# 2. Repo-specific AGENTS.md for context
# 3. Issue body for task details
# 4. Previous role output (e.g., architect plan for implement)

set -euo pipefail

# Resolve the prompt template path for a role.
# Priority: repo-local override > mango-workflows shared template.
# Usage: prompt_resolve_path CONFIG_FILE ROLE_NAME REPO_ROOT WORKFLOWS_ROOT
# Output: absolute path to the prompt template file
prompt_resolve_path() {
  local config="$1" role="$2" repo_root="$3" workflows_root="$4"

  # 1. Check config for explicit prompt path (repo-local)
  local config_prompt
  config_prompt=$(jq -r ".agentRoles.roles[\"$role\"].prompt // empty" "$config")

  if [ -n "$config_prompt" ] && [ -f "$repo_root/$config_prompt" ]; then
    echo "$repo_root/$config_prompt"
    return 0
  fi

  # 2. Fallback to shared template in mango-workflows
  local shared="$workflows_root/prompts/${role}.md"
  if [ -f "$shared" ]; then
    echo "$shared"
    return 0
  fi

  # 3. No template found
  return 1
}

# Read the AGENTS.md from the consumer repo (if it exists)
# Usage: prompt_read_agents_md REPO_ROOT
# Output: contents of AGENTS.md, or empty
prompt_read_agents_md() {
  local repo_root="$1"

  if [ -f "$repo_root/AGENTS.md" ]; then
    cat "$repo_root/AGENTS.md"
  fi
}

# Build the full prompt for a role by combining template + context
# Usage: prompt_build CONFIG_FILE ROLE_NAME REPO_ROOT WORKFLOWS_ROOT ISSUE_BODY [PREV_OUTPUT]
# Output: assembled prompt text to stdout
prompt_build() {
  local config="$1" role="$2" repo_root="$3" workflows_root="$4" issue_body="$5"
  local prev_output="${6:-}"

  # Resolve template
  local template_path
  template_path=$(prompt_resolve_path "$config" "$role" "$repo_root" "$workflows_root") || {
    echo "ERROR: No prompt template found for role '$role'"
    return 1
  }

  local template
  template=$(cat "$template_path")

  # Read repo context
  local agents_md
  agents_md=$(prompt_read_agents_md "$repo_root")

  # Variable substitution in template
  # Supported placeholders:
  #   {{ISSUE_BODY}}     — the issue description
  #   {{AGENTS_MD}}      — the repo's AGENTS.md
  #   {{PREV_OUTPUT}}    — output from previous role (e.g., architect plan)
  #   {{ROLE}}           — current role name
  local result="$template"
  result="${result//\{\{ISSUE_BODY\}\}/$issue_body}"
  result="${result//\{\{ROLE\}\}/$role}"

  if [ -n "$agents_md" ]; then
    result="${result//\{\{AGENTS_MD\}\}/$agents_md}"
  else
    result="${result//\{\{AGENTS_MD\}\}/No AGENTS.md found in this repository.}"
  fi

  if [ -n "$prev_output" ]; then
    result="${result//\{\{PREV_OUTPUT\}\}/$prev_output}"
  else
    result="${result//\{\{PREV_OUTPUT\}\}/No previous role output available.}"
  fi

  echo "$result"
}

# Check if a prompt template exists for a role
# Usage: prompt_exists CONFIG_FILE ROLE_NAME REPO_ROOT WORKFLOWS_ROOT
# Exit: 0 if exists, 1 if not
prompt_exists() {
  local config="$1" role="$2" repo_root="$3" workflows_root="$4"
  prompt_resolve_path "$config" "$role" "$repo_root" "$workflows_root" > /dev/null 2>&1
}
