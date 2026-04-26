#!/usr/bin/env bash
# Shell library for retry logic (count, provider alternation, escalation)
# Source this file: source lib/retry.sh

set -euo pipefail

# Count retry labels from a JSON array of label names
# Usage: retry_count_from_labels LABELS_JSON
# Output: integer count
retry_count_from_labels() {
  local labels_json="$1"
  echo "$labels_json" | jq -r '[.[] | select(startswith("retry:"))] | length'
}

# Determine next provider based on retry number
# Usage: retry_next_provider RETRY_NUM PRIMARY FALLBACK
# Output: provider name
retry_next_provider() {
  local retry_num="$1" primary="$2" fallback="${3:-}"
  if [ -z "$fallback" ]; then
    echo "$primary"
    return 0
  fi
  # Odd retries use fallback, even retries use primary
  if (( retry_num % 2 == 1 )); then
    echo "$fallback"
  else
    echo "$primary"
  fi
}

# Check if retries are exhausted and should escalate to human
# Usage: retry_should_escalate RETRY_COUNT MAX_RETRIES
# Exit: 0 if should escalate, 1 if can still retry
retry_should_escalate() {
  local retry_count="$1" max_retries="$2"
  if [ "$retry_count" -gt "$max_retries" ]; then
    return 0
  else
    return 1
  fi
}
