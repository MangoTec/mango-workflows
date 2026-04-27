#!/usr/bin/env bash
# Wave Ready — main logic for consolidated PR creation and finalization.
# Called from .github/workflows/wave-ready.yml
# Expects: GH_TOKEN, GH_PAT_PORTAL, SLACK_WEBHOOK_URL (or fallback secret),
#           GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_EVENT_PATH env vars.

set -euo pipefail
# shellcheck disable=SC2016

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/mission.sh"
source "${SCRIPT_DIR}/waves.sh"

MISSIONS_DIR=".github/missions"
TOKEN="${GH_TOKEN}"
# PAT with PR creation permissions (GITHUB_TOKEN may lack this)
PAT="${GH_PAT_PORTAL:-$TOKEN}"
REPO="${GITHUB_REPOSITORY}"
REPO_NAME=$(basename "$REPO")
VERIFY_DEPS_READY=false

gh_auth() {
  GH_TOKEN="$TOKEN" gh "$@"
}

# Use PAT for operations that GITHUB_TOKEN may not be allowed to do
gh_pat() {
  GH_TOKEN="$PAT" gh "$@"
}

notify_slack() {
  local message="$1"

  if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "::warning::Slack webhook is empty; notification skipped. Configure MANGO_TL_REMINDERS_SLACK_WEBHOOK_URL or SLACK_WEBHOOK_URL."
    return 0
  fi

  curl -sf -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"text\": $(echo "$message" | jq -Rs .)}" >/dev/null \
    || echo "::warning::Slack notification failed"
}

truthy() {
  case "${1,,}" in
    true|1|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_copilot_pr_author() {
  case "$1" in
    app/copilot-swe-agent|Copilot|copilot-swe-agent|github-copilot)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copilot_agent_succeeded_for_ref() {
  local ref_name="$1"
  local matches

  matches=$(gh_auth run list \
    --workflow "Copilot cloud agent" \
    --branch "$ref_name" \
    --limit 10 \
    --json status,conclusion \
    --jq '[.[] | select(.status == "completed" and .conclusion == "success")] | length' \
    2>/dev/null || echo "0")

  [ "${matches:-0}" -gt 0 ]
}

accept_copilot_draft_pr_after_success() {
  local config="$1" pr_json="$2"
  local accept author ref_name pr_number

  accept=$(jq -r '.agent.providers.copilot.acceptDraftPrsAfterAgentSuccess // true' "$config")
  truthy "$accept" || return 1

  author=$(jq -r '.author.login // empty' <<< "$pr_json")
  is_copilot_pr_author "$author" || return 1

  ref_name=$(jq -r '.headRefName' <<< "$pr_json")
  pr_number=$(jq -r '.number' <<< "$pr_json")

  if copilot_agent_succeeded_for_ref "$ref_name"; then
    echo "Accepting draft Copilot PR #$pr_number ($ref_name) because Copilot cloud agent completed successfully for the branch"
    return 0
  fi

  return 1
}

apply_verification_env() {
  local config="$1" key value

  # Mission configs may define repo-specific verification env, e.g.
  # {"verification":{"env":{"API_BASE_URL":"https://api.example.test/api"}}}
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue

    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < <(jq -r '.verification.env // {} | to_entries[] | "\(.key)=\(.value | tostring)"' "$config" 2>/dev/null || true)

  # Safe defaults for Mango Next.js apps. These match CI placeholders and keep
  # build/typecheck hooks deterministic when the caller workflow has no env.
  export API_BASE_URL="${API_BASE_URL:-https://api.example.test/api}"
  export JWT_SECRET="${JWT_SECRET:-ci-test-secret-value-for-github-actions-32}"
  export AUTH_COOKIE_NAME="${AUTH_COOKIE_NAME:-auth-session}"
}

ensure_verify_dependencies() {
  local install_cmd install_output install_exit

  if [ "$VERIFY_DEPS_READY" = true ]; then
    return 0
  fi

  if [ ! -f package.json ]; then
    VERIFY_DEPS_READY=true
    return 0
  fi

  if [ -f package-lock.json ]; then
    install_cmd="npm ci --prefer-offline --no-audit"
  else
    install_cmd="npm install --no-audit"
  fi

  echo "Installing dependencies for verification: $install_cmd"
  set +e
  install_output=$(eval "$install_cmd" 2>&1)
  install_exit=$?
  set -e

  if [ "$install_exit" -ne 0 ]; then
    printf '### ❌ `install` failed (exit %s)\n```\n%s\n```\n' \
      "$install_exit" "$(echo "$install_output" | tail -50)" \
      > /tmp/wave-verify-errors.md
    return 1
  fi

  echo "$install_output" | tail -20
  VERIFY_DEPS_READY=true
  return 0
}

wave_consolidated_branch() {
  local mission_id="$1" mission_branch="$2" base_branch="$3" wave="$4"

  if [ "$mission_id" = "default" ] && [ "$mission_branch" = "$base_branch" ]; then
    echo "wave-${wave}/consolidate"
  else
    # Use -- separator instead of / to avoid Git ref conflict when mission_branch
    # exists as a ref (e.g. mission/estado-de-cuenta cannot coexist with
    # mission/estado-de-cuenta/wave-1/consolidate).
    echo "consolidate/${mission_id}--wave-${wave}"
  fi
}

unlock_next_wave() {
  local config="$1" next_wave="$2"
  local issue_num
  mapfile -t NEXT_ISSUES < <(wave_get_issues "$config" "$next_wave")

  for issue_num in "${NEXT_ISSUES[@]}"; do
    # Use the PAT-backed client here instead of GITHUB_TOKEN. Label events
    # created by GITHUB_TOKEN/GitHub Actions do not trigger downstream
    # workflows, so `status:ready` would be applied but Assign Agent would
    # never start the next wave.
    gh_pat issue edit "$issue_num" \
      --remove-label "status:blocked" \
      --add-label "status:ready" 2>/dev/null || true
  done
}

create_final_pr_if_needed() {
  local config="$1" mission_id="$2"
  local mission_branch base_branch pr_title pr_body all_issues wave issue_num final_pr

  mission_branch=$(mission_get_branch_from_config "$config")
  base_branch=$(mission_get_base_branch_from_config "$config")

  if [ "$mission_branch" = "$base_branch" ]; then
    echo "Mission branch is base branch ($base_branch); no final PR needed."
    return 0
  fi

  all_issues=""
  for wave in $(jq -r '.waves | keys[]' "$config" | sort -n); do
    mapfile -t WAVE_ISSUES < <(wave_get_issues "$config" "$wave")
    for issue_num in "${WAVE_ISSUES[@]}"; do
      all_issues="${all_issues}- Closes #${issue_num}"$'\n'
    done
  done

  pr_title="feat(${mission_id}): complete mission"
  pr_body=$(printf '## Mission `%s` — Final PR\n\nAll waves complete. This PR merges the full mission branch into `%s`.\n\n### Issues included\n%s\n### Review\nReview the combined changes, approve, and merge.' "$mission_id" "$base_branch" "$all_issues")

  final_pr=$(gh_pat pr create \
    --base "$base_branch" \
    --head "$mission_branch" \
    --title "$pr_title" \
    --body "$pr_body" 2>&1) || {
    echo "::warning::Could not create final PR (may already exist): $final_pr"
    final_pr=$(gh_auth pr list --base "$base_branch" --head "$mission_branch" --json url --jq '.[0].url // empty')
  }

  echo "$final_pr"
}

run_verify_hooks() {
  local config="$1" wave="$2"
  local verify_passed=true verify_errors="" hook_name hook_cmd hook_output hook_exit
  mapfile -t VERIFY_HOOKS < <(wave_get_verify_hooks "$config" "$wave")

  if [ "${#VERIFY_HOOKS[@]}" -eq 0 ]; then
    return 0
  fi

  apply_verification_env "$config"
  if ! ensure_verify_dependencies; then
    return 1
  fi

  for hook_name in "${VERIFY_HOOKS[@]}"; do
    hook_cmd=$(jq -r ".verification.hooks[\"$hook_name\"] // empty" "$config")
    if [ -z "$hook_cmd" ]; then
      echo "::warning::Verify hook '$hook_name' not found in verification.hooks"
      continue
    fi

    echo "Running verify hook: $hook_name → $hook_cmd"
    set +e
    hook_output=$(eval "$hook_cmd" 2>&1)
    hook_exit=$?
    set -e

    if [ "$hook_exit" -ne 0 ]; then
      verify_passed=false
      verify_errors="${verify_errors}"$'\n'"### ❌ \`$hook_name\` failed (exit $hook_exit)"$'\n```\n'"$(echo "$hook_output" | tail -50)"$'\n```\n'
    else
      echo "✅ $hook_name passed"
    fi
  done

  if [ "$verify_passed" = "true" ]; then
    return 0
  fi

  printf '%s' "$verify_errors" > /tmp/wave-verify-errors.md
  return 1
}

finalize_merged_wave_pr() {
  local event_head event_base event_number event_url config mission_id base_branch mission_branch wave consolidated_branch legacy_branch
  local matched_config="" matched_wave="" issue_num gate_type gate_issue next_wave final_pr run_url next_count state

  event_head=$(jq -r '.pull_request.head.ref // empty' "$GITHUB_EVENT_PATH")
  event_base=$(jq -r '.pull_request.base.ref // empty' "$GITHUB_EVENT_PATH")
  event_number=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")
  event_url=$(jq -r '.pull_request.html_url // empty' "$GITHUB_EVENT_PATH")

  if [ -z "$event_head" ] || [ -z "$event_base" ]; then
    return 1
  fi

  for config in $(mission_list_active_configs "$MISSIONS_DIR"); do
    mission_id=$(mission_get_id "$config")
    base_branch=$(mission_get_base_branch_from_config "$config")
    mission_branch=$(mission_get_branch_from_config "$config")

    for wave in $(jq -r '.waves | keys[]' "$config" | sort -n); do
      consolidated_branch=$(wave_consolidated_branch "$mission_id" "$mission_branch" "$base_branch" "$wave")
      legacy_branch="wave-${wave}/consolidate"

      if [ "$event_base" = "$mission_branch" ] && { [ "$event_head" = "$consolidated_branch" ] || [ "$event_head" = "$legacy_branch" ]; }; then
        matched_config="$config"
        matched_wave="$wave"
        break 2
      fi
    done
  done

  if [ -z "$matched_config" ] || [ -z "$matched_wave" ]; then
    echo "Merged PR head '$event_head' into '$event_base' is not a known consolidated wave PR."
    return 1
  fi

  config="$matched_config"
  wave="$matched_wave"
  mission_id=$(mission_get_id "$config")
  base_branch=$(mission_get_base_branch_from_config "$config")
  mission_branch=$(mission_get_branch_from_config "$config")
  next_wave=$((wave + 1))
  gate_type=$(wave_get_gate_type "$config" "$wave")
  gate_issue=$(jq -r ".waveGates[\"$wave\"] // empty" "$config")

  echo "Finalizing merged wave PR #$event_number for mission=$mission_id wave=$wave gate=$gate_type"

  git fetch origin "$mission_branch" --prune 2>/dev/null || true
  git checkout --detach "origin/$mission_branch" 2>/dev/null || true

  mapfile -t WAVE_ISSUES < <(wave_get_issues "$config" "$wave")
  for issue_num in "${WAVE_ISSUES[@]}"; do
    state=$(gh_auth issue view "$issue_num" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
    if [ "$state" = "OPEN" ]; then
      gh_auth issue close "$issue_num" \
        --comment "✅ Implementado y mergeado en la PR consolidada #${event_number}: ${event_url}" \
        2>/dev/null || true
    else
      gh_auth issue comment "$issue_num" \
        --body "✅ Incluido en la PR consolidada #${event_number}: ${event_url}" \
        2>/dev/null || true
    fi
  done

  # Close individual task PRs (never merged — consolidated PR replaces them)
  local all_open_prs child_pr_numbers pr_num
  all_open_prs=$(gh_auth pr list --state open --limit 200 \
    --json number,headRefName,baseRefName,closingIssuesReferences 2>/dev/null || echo "[]")
  for issue_num in "${WAVE_ISSUES[@]}"; do
    child_pr_numbers=$(jq -r --argjson issue "$issue_num" --arg event_head "$event_head" '
      [ .[]
        | select(.headRefName != $event_head)
        | select((.headRefName | test("(^|/)wave-[0-9]+/consolidate$|^consolidate/")) | not)
        | select(any(.closingIssuesReferences[]?; .number == $issue))
        | .number
      ] | .[]
    ' <<< "$all_open_prs")
    for pr_num in $child_pr_numbers; do
      gh_auth pr close "$pr_num" \
        --comment "✅ Included in consolidated wave PR #${event_number}. This PR was not merged directly." \
        2>/dev/null || true
    done
  done

  if [ "$(jq -r '.cleanup.removeLabelsOnComplete // false' "$config")" = "true" ]; then
    local label
    for issue_num in "${WAVE_ISSUES[@]}"; do
      for label in status:ready status:in-progress status:blocked status:failed status:spec-invalid needs-human; do
        gh_auth issue edit "$issue_num" --remove-label "$label" 2>/dev/null || true
      done
    done
  fi

  if [ "$(jq -r '.cleanup.deleteMergedTaskBranches // false' "$config")" = "true" ]; then
    local prs_json ref_name del_base_branch
    del_base_branch=$(jq -r '.mission.baseBranch // "main"' "$config")
    # Fetch PRs targeting both mission branch and base branch (Copilot PRs target base)
    prs_json=$(jq -s 'add | unique_by(.number)' \
      <(gh_auth pr list --base "$mission_branch" --state all --limit 200 \
        --json number,headRefName,closingIssuesReferences) \
      <(gh_auth pr list --base "$del_base_branch" --state all --limit 200 \
        --json number,headRefName,closingIssuesReferences))
    for issue_num in "${WAVE_ISSUES[@]}"; do
      ref_name=$(jq -r --argjson issue "$issue_num" --arg event_head "$event_head" '
        [ .[]
          | select(.headRefName != $event_head)
          | select((.headRefName | test("(^|/)wave-[0-9]+/consolidate$|^consolidate/")) | not)
          | select(any(.closingIssuesReferences[]?; .number == $issue))
        ]
        | sort_by(.number)
        | last.headRefName // empty
      ' <<< "$prs_json")
      if [ -n "$ref_name" ]; then
        git push origin --delete "$ref_name" 2>/dev/null || true
      fi
    done
  fi

  if wave_exists "$config" "$next_wave"; then
    case "$gate_type" in
      human)
        unlock_next_wave "$config" "$next_wave"
        if [ -n "$gate_issue" ] && [ "$gate_issue" != "null" ]; then
          gh_auth issue comment "$gate_issue" --body "✅ **Wave $wave approved via consolidated PR #$event_number.** Wave $next_wave unlocked."
          gh_auth issue edit "$gate_issue" --add-label "gate:approved" 2>/dev/null || true
          if [ "$(jq -r '.cleanup.closeResolvedGateIssues // false' "$config")" = "true" ]; then
            gh_auth issue close "$gate_issue" --reason completed 2>/dev/null || true
          fi
        fi
        ;;
      verify-then-auto)
        if run_verify_hooks "$config" "$wave"; then
          unlock_next_wave "$config" "$next_wave"
          if [ -n "$gate_issue" ] && [ "$gate_issue" != "null" ]; then
            gh_auth issue comment "$gate_issue" --body "🟢 **Wave $wave verified and auto-approved after PR #$event_number.** Wave $next_wave unlocked."
            if [ "$(jq -r '.cleanup.closeResolvedGateIssues // false' "$config")" = "true" ]; then
              gh_auth issue close "$gate_issue" --reason completed 2>/dev/null || true
            fi
          fi
        else
          local comment
          comment=$(printf '🔴 **Verification failed for wave %s after consolidated PR #%s.** Re-opened for fixes.\n\n%s' "$wave" "$event_number" "$(cat /tmp/wave-verify-errors.md)")
          for issue_num in "${WAVE_ISSUES[@]}"; do
            gh_auth api "repos/${REPO}/issues/$issue_num" -X PATCH -f state=open 2>/dev/null || true
            gh_auth issue comment "$issue_num" --body "$comment" 2>/dev/null || true
            gh_auth issue edit "$issue_num" --add-label "status:ready" 2>/dev/null || true
          done
          run_url="https://github.com/${REPO}/actions/runs/${GITHUB_RUN_ID}"
          notify_slack "🔴 *Verificación falló en wave ${wave}*\n• Repo: \`${REPO_NAME}\`\n• Issues re-abiertos\n• Run: <${run_url}|ver ejecución>"
          return 0
        fi
        ;;
      auto|*)
        unlock_next_wave "$config" "$next_wave"
        ;;
    esac

    mapfile -t NEXT_ISSUES < <(wave_get_issues "$config" "$next_wave")
    next_count="${#NEXT_ISSUES[@]}"
    run_url="https://github.com/${REPO}/actions/runs/${GITHUB_RUN_ID}"
    notify_slack "🚀 *Wave ${next_wave} desbloqueada*\n• Repo: \`${REPO_NAME}\`\n• Misión: \`${mission_id}\`\n• PR consolidada: <${event_url}|#${event_number}>\n• Issues listas: ${next_count}\n• Run: <${run_url}|ver ejecución>"
  else
    final_pr=$(create_final_pr_if_needed "$config" "$mission_id")
    if [ -n "$gate_issue" ] && [ "$gate_issue" != "null" ]; then
      gh_auth issue comment "$gate_issue" --body "🎊 **All waves complete!** Final PR: ${final_pr:-no final PR needed}."
      if [ "$(jq -r '.cleanup.closeResolvedGateIssues // false' "$config")" = "true" ]; then
        gh_auth issue close "$gate_issue" --reason completed 2>/dev/null || true
      fi
    fi
    notify_slack "🎊 *Misión completa*\n• Repo: \`${REPO_NAME}\`\n• Misión: \`${mission_id}\`\n• Final PR: ${final_pr:-no aplica}"
  fi

  return 0
}

# ── Main entry point ──────────────────────────────────────────────

EVENT_IS_MERGED_PR=false
if [ -f "$GITHUB_EVENT_PATH" ]; then
  EVENT_IS_MERGED_PR=$(jq -r '(.pull_request.merged // false) | tostring' "$GITHUB_EVENT_PATH")
fi

if [ "$EVENT_IS_MERGED_PR" = "true" ]; then
  if finalize_merged_wave_pr; then
    exit 0
  fi
fi

# Configure git remote to use PAT for push (falls back to github.token).
PAT_FOR_PUSH="${GH_PAT_PORTAL:-$GH_TOKEN}"
git remote set-url origin "https://x-access-token:${PAT_FOR_PUSH}@github.com/${REPO}.git"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

OPEN_PRS_JSON=$(gh_auth pr list --state open --limit 200 \
  --json number,title,author,headRefName,headRefOid,baseRefName,isDraft,url,mergeStateStatus,closingIssuesReferences)

# Iterate over all active mission configs
for CONFIG in $(mission_list_active_configs "$MISSIONS_DIR"); do
  MISSION_ID=$(mission_get_id "$CONFIG")
  BASE_BRANCH=$(mission_get_base_branch_from_config "$CONFIG")
  MISSION_BRANCH=$(mission_get_branch_from_config "$CONFIG")

  echo "=== Processing mission: $MISSION_ID (base: $BASE_BRANCH, branch: $MISSION_BRANCH) ==="
  git fetch origin "$BASE_BRANCH" --prune 2>/dev/null || true

  if [ "$MISSION_BRANCH" != "$BASE_BRANCH" ]; then
    if git ls-remote --exit-code --heads origin "$MISSION_BRANCH" >/dev/null 2>&1; then
      git fetch origin "$MISSION_BRANCH" --prune
    else
      echo "Mission branch $MISSION_BRANCH does not exist; creating it from $BASE_BRANCH"
      git checkout -B "$MISSION_BRANCH" "origin/$BASE_BRANCH"
      git push origin "$MISSION_BRANCH"
    fi
  fi

  mapfile -t WAVES < <(jq -r '.waves | keys[]' "$CONFIG" | sort -n)

  for WAVE in "${WAVES[@]}"; do
    CONSOLIDATED_BRANCH=$(wave_consolidated_branch "$MISSION_ID" "$MISSION_BRANCH" "$BASE_BRANCH" "$WAVE")
    NEXT_WAVE=$((WAVE + 1))
    GATE_ISSUE=$(jq -r ".waveGates[\"$WAVE\"] // empty" "$CONFIG")

    if gh_auth pr list --head "$CONSOLIDATED_BRANCH" --base "$MISSION_BRANCH" --state merged --json number --jq 'length > 0' | grep -q true; then
      echo "Wave $WAVE already merged via $CONSOLIDATED_BRANCH"
      continue
    fi

    if [ -n "$GATE_ISSUE" ] && [ "$GATE_ISSUE" != "null" ]; then
      GATE_STATE=$(gh_auth issue view "$GATE_ISSUE" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
      if [ "$GATE_STATE" = "CLOSED" ]; then
        echo "Gate #$GATE_ISSUE already closed for wave $WAVE"
        continue
      fi
    fi

    mapfile -t ISSUE_NUMBERS < <(wave_get_issues "$CONFIG" "$WAVE")

    if [ "${#ISSUE_NUMBERS[@]}" -eq 0 ]; then
      continue
    fi

    declare -a CHILD_ISSUES=()
    declare -a CHILD_PRS=()
    declare -a CHILD_REFS=()
    declare -a CHILD_URLS=()
    declare -a CHILD_TITLES=()

    WAVE_READY=true

    for ISSUE_NUMBER in "${ISSUE_NUMBERS[@]}"; do
      # Accept PRs targeting either the mission branch OR the base branch (main).
      # Copilot coding agent always creates PRs against the default branch (main),
      # so we accept those as source material for the consolidated wave PR.
      PR_JSON=$(jq -c --argjson issue "$ISSUE_NUMBER" --arg base "$MISSION_BRANCH" --arg default_base "$BASE_BRANCH" --arg consolidated "$CONSOLIDATED_BRANCH" '
          [ .[]
            | select(.baseRefName == $base or .baseRefName == $default_base)
            | select(.headRefName != $consolidated)
            | select((.headRefName | test("(^|/)wave-[0-9]+/consolidate$|^consolidate/")) | not)
            | select(any(.closingIssuesReferences[]?; .number == $issue))
          ]
          | sort_by(.number)
          | last // empty
        ' <<< "$OPEN_PRS_JSON")

      if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "null" ]; then
        echo "Wave $WAVE not ready: missing open PR for issue #$ISSUE_NUMBER"
        WAVE_READY=false
        break
      fi

      # Individual PRs are never merged directly — they are source material for
      # the consolidated wave PR. Human drafts are not ready; Copilot drafts
      # are accepted once the Copilot cloud agent run succeeded for the exact
      # PR head SHA because Copilot leaves implementation PRs in draft.
      IS_DRAFT=$(jq -r '.isDraft' <<< "$PR_JSON")
      if [ "$IS_DRAFT" = "true" ]; then
        if ! accept_copilot_draft_pr_after_success "$CONFIG" "$PR_JSON"; then
          echo "Wave $WAVE not ready: PR for issue #$ISSUE_NUMBER is still a draft"
          WAVE_READY=false
          break
        fi
      fi

      CHILD_ISSUES+=("$ISSUE_NUMBER")
      CHILD_PRS+=("$(jq -r '.number' <<< "$PR_JSON")")
      CHILD_REFS+=("$(jq -r '.headRefName' <<< "$PR_JSON")")
      CHILD_URLS+=("$(jq -r '.url' <<< "$PR_JSON")")
      CHILD_TITLES+=("$(jq -r '.title' <<< "$PR_JSON")")
    done

    if [ "$WAVE_READY" != "true" ]; then
      continue
    fi

    echo "Wave $WAVE is ready for consolidation (${#CHILD_REFS[@]} PRs)"

    REMOTE_BRANCH_EXISTS=false
    if [ -n "$(git ls-remote --heads origin "$CONSOLIDATED_BRANCH")" ]; then
      REMOTE_BRANCH_EXISTS=true
      git fetch origin "$CONSOLIDATED_BRANCH"
    fi

    git checkout -B "$CONSOLIDATED_BRANCH" "origin/$MISSION_BRANCH"

    for index in "${!CHILD_REFS[@]}"; do
      REF_NAME="${CHILD_REFS[$index]}"
      ISSUE_NUMBER="${CHILD_ISSUES[$index]}"
      PR_NUMBER="${CHILD_PRS[$index]}"

      echo "Merging $REF_NAME (PR #$PR_NUMBER, issue #$ISSUE_NUMBER)"
      git fetch origin "$REF_NAME"

      if ! git merge --no-ff --no-edit FETCH_HEAD; then
        # Copilot PRs target main, not the mission branch, so add/add conflicts
        # are expected when wave N evolves files created in wave N-1.
        # Retry with -X theirs to accept the PR's (newer) version.
        echo "Merge conflict detected — retrying with -X theirs (accept PR version)"
        git merge --abort || true

        if ! git merge --no-ff --no-edit -X theirs FETCH_HEAD; then
          git merge --abort || true

          RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
          CONFLICT_MESSAGE=$(printf '%s\n' \
            "🔴 *Consolidación fallida en wave ${WAVE}*" \
            "• Repo: \`${REPO_NAME}\`" \
            "• PR en conflicto: <${CHILD_URLS[$index]}|#${PR_NUMBER}> (issue #${ISSUE_NUMBER})" \
            "• Branch objetivo: \`${CONSOLIDATED_BRANCH}\`" \
            "• Run: <${RUN_URL}|ver ejecución>" \
            "• Acción: resolver conflicto en PR hija y relanzar workflow")
          notify_slack "$CONFLICT_MESSAGE"

          if [ -n "$GATE_ISSUE" ] && [ "$GATE_ISSUE" != "null" ]; then
            gh_auth issue comment "$GATE_ISSUE" --body "⚠️ **Wave $WAVE consolidation failed** due to a merge conflict while applying PR #$PR_NUMBER for issue #$ISSUE_NUMBER. Resolve the child PR conflict and rerun the workflow."
          fi

          exit 1
        fi
      fi
    done

    # ── Pre-PR verification gate ──────────────────────────────────
    # Run verify hooks on the consolidated branch BEFORE creating/updating
    # the PR. This catches broken tests, lint errors, and type errors early
    # — before CI runs on the PR and before a human has to intervene.
    if [ "$(wave_get_gate_type "$CONFIG" "$WAVE")" = "verify-then-auto" ]; then
      echo "Running pre-PR verification hooks on consolidated branch..."

      if ! run_verify_hooks "$CONFIG" "$WAVE"; then
        VERIFY_ERRORS=$(cat /tmp/wave-verify-errors.md 2>/dev/null || echo "Unknown verification failure")
        RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

        # Notify on gate issue
        if [ -n "$GATE_ISSUE" ] && [ "$GATE_ISSUE" != "null" ]; then
          gh_auth issue comment "$GATE_ISSUE" --body "$(printf '🔴 **Pre-PR verification failed for wave %s.**\n\nThe consolidated branch did not pass verification hooks. PR was NOT created.\n\n%s\n\nRun: %s' "$WAVE" "$VERIFY_ERRORS" "$RUN_URL")"
        fi

        # Notify Slack
        notify_slack "$(printf '%s\n' \
          "🔴 *Verificación pre-PR falló en wave ${WAVE}*" \
          "• Repo: \`${REPO_NAME}\`" \
          "• Misión: \`${MISSION_ID}\`" \
          "• La PR consolidada NO se creó" \
          "• Run: <${RUN_URL}|ver ejecución>" \
          "• Acción: corregir errores en las PRs hijas y relanzar")"

        # Re-label task issues as needing fixes
        for issue_num in "${CHILD_ISSUES[@]}"; do
          gh_auth issue edit "$issue_num" --add-label "status:failed" 2>/dev/null || true
          gh_auth issue comment "$issue_num" --body "$(printf '🔴 Pre-PR verification failed. Fix required before consolidation.\n\n%s' "$VERIFY_ERRORS")" 2>/dev/null || true
        done

        echo "::error::Pre-PR verification failed for wave $WAVE. PR not created."
        continue
      fi

      echo "✅ Pre-PR verification passed for wave $WAVE"
    fi

    BODY_FILE=$(mktemp)
    {
      echo "## Wave $WAVE Consolidation"
      echo
      echo "This PR consolidates the completed task PRs for wave $WAVE into a single review point."
      echo
      echo "### Included task PRs"
      for index in "${!CHILD_REFS[@]}"; do
        echo "- Includes #${CHILD_ISSUES[$index]}: ${CHILD_TITLES[$index]} ([#${CHILD_PRS[$index]}](${CHILD_URLS[$index]}))"
      done
      echo
      echo "### Automation"
      echo "- Merging this PR closes the wave issues from automation, even when the PR targets a non-default mission branch."

      if jq -e ".waves[\"$NEXT_WAVE\"]" "$CONFIG" >/dev/null 2>&1; then
        echo "- After merge, automation applies the wave gate and starts wave $NEXT_WAVE when allowed."
      else
        echo "- After merge, automation completes the final wave and creates the final mission PR when needed."
      fi
    } > "$BODY_FILE"

    OPEN_WAVE_PR_NUMBER=$(gh_auth pr list --head "$CONSOLIDATED_BRANCH" --base "$MISSION_BRANCH" --state open --json number --jq '.[0].number // empty')
    PR_CREATED=false

    if [ "$REMOTE_BRANCH_EXISTS" = true ] && git diff --quiet "origin/$CONSOLIDATED_BRANCH...HEAD"; then
      echo "No content changes detected for $CONSOLIDATED_BRANCH"
    else
      git push origin "$CONSOLIDATED_BRANCH" --force-with-lease
    fi

    TITLE="feat(${MISSION_ID}/wave-$WAVE): consolidate ${#CHILD_REFS[@]} completed tasks"

    if [ -n "$OPEN_WAVE_PR_NUMBER" ]; then
      gh_pat pr edit "$OPEN_WAVE_PR_NUMBER" --title "$TITLE" --body-file "$BODY_FILE"
    else
      gh_pat pr create --base "$MISSION_BRANCH" --head "$CONSOLIDATED_BRANCH" --title "$TITLE" --body-file "$BODY_FILE"
      PR_CREATED=true
    fi

    WAVE_PR_NUMBER=$(gh_auth pr list --head "$CONSOLIDATED_BRANCH" --base "$MISSION_BRANCH" --state open --json number,url --jq '.[0].number // empty')
    WAVE_PR_URL=$(gh_auth pr list --head "$CONSOLIDATED_BRANCH" --base "$MISSION_BRANCH" --state open --json number,url --jq '.[0].url // empty')

    if [ "$PR_CREATED" = true ]; then
      if [ -n "$GATE_ISSUE" ] && [ "$GATE_ISSUE" != "null" ]; then
        gh_auth issue comment "$GATE_ISSUE" --body "🧪 **Wave $WAVE is ready for review.** Consolidated PR: <${WAVE_PR_URL}|#${WAVE_PR_NUMBER}>. Merge this PR to apply the gate and continue."
      fi

      RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
      if jq -e ".waves[\"$NEXT_WAVE\"]" "$CONFIG" >/dev/null 2>&1; then
        SLACK_MESSAGE=$(printf '%s\n' \
          "🟢 *Wave ${WAVE} lista para revisión*" \
          "• Repo: \`${REPO_NAME}\`" \
          "• Misión: \`${MISSION_ID}\`" \
          "• PR consolidada: <${WAVE_PR_URL}|#${WAVE_PR_NUMBER}>" \
          "• Tareas incluidas: ${#CHILD_REFS[@]}" \
          "• Siguiente paso: mergear PR para arrancar wave ${NEXT_WAVE}" \
          "• Run: <${RUN_URL}|ver ejecución>")
      else
        SLACK_MESSAGE=$(printf '%s\n' \
          "🟢 *Wave ${WAVE} lista para revisión (final)*" \
          "• Repo: \`${REPO_NAME}\`" \
          "• Misión: \`${MISSION_ID}\`" \
          "• PR consolidada: <${WAVE_PR_URL}|#${WAVE_PR_NUMBER}>" \
          "• Tareas incluidas: ${#CHILD_REFS[@]}" \
          "• Siguiente paso: mergear PR para finalizar la pipeline" \
          "• Run: <${RUN_URL}|ver ejecución>")
      fi

      notify_slack "$SLACK_MESSAGE"
    fi

    rm -f "$BODY_FILE"
  done
done
