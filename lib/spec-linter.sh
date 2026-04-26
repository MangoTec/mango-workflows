#!/usr/bin/env bash
# Shell library for spec linting (validates issue body against config rules)
# Source this file: source lib/spec-linter.sh

set -euo pipefail

# Check body length meets minimum
# Usage: lint_body_length BODY MIN_LENGTH
# Output: error message or empty; exit 0 always
lint_body_length() {
  local body="$1" min_length="$2"
  local body_length=${#body}
  if [ "$body_length" -lt "$min_length" ]; then
    echo "Body too short (${body_length} chars, minimum: ${min_length})"
  fi
}

# Check required sections exist in body
# Usage: lint_required_sections BODY SECTIONS_PIPE_DELIMITED
# Output: one error line per missing section, or empty
lint_required_sections() {
  local body="$1" sections_str="$2"
  local section
  IFS='|' read -ra SECTIONS <<< "$sections_str"
  for section in "${SECTIONS[@]}"; do
    if ! echo "$body" | grep -qiE "^#{1,3} *${section}"; then
      echo "Missing required section: ${section}"
    fi
  done
}

# Check file references in body exist on disk
# Usage: lint_file_refs BODY REPO_ROOT
# Output: one error line per missing file, or empty
lint_file_refs() {
  local body="$1" repo_root="$2"
  local ref
  local file_refs
  # shellcheck disable=SC2016
  file_refs=$(echo "$body" | grep -oE '`[a-zA-Z0-9_./-]+\.(ts|tsx|js|jsx|php|yml|yaml|json|md|css|html)`' | tr -d '`' | sort -u)
  for ref in $file_refs; do
    if [ ! -f "$repo_root/$ref" ]; then
      echo "Referenced file not found: $ref"
    fi
  done
}

# Check body mentions the spec source
# Usage: lint_spec_source BODY SPEC_SOURCE
# Output: error message or empty
lint_spec_source() {
  local body="$1" spec_source="$2"
  if [ -z "$spec_source" ]; then
    return 0
  fi
  if ! echo "$body" | grep -qF "$spec_source"; then
    echo "Spec does not reference source-of-truth: $spec_source"
  fi
}
