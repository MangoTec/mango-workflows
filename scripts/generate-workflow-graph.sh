#!/usr/bin/env bash

set -euo pipefail

REPO="${1:-MangoTec/mango-portal}"
OUTPUT_BASE="${2:-status/workflow-status}"

if [[ "$OUTPUT_BASE" == *.md || "$OUTPUT_BASE" == *.json || "$OUTPUT_BASE" == *.html ]]; then
  OUTPUT_BASE="${OUTPUT_BASE%.*}"
fi

OUTPUT_JSON="${OUTPUT_BASE}.json"
OUTPUT_HTML="${OUTPUT_BASE}.html"

mkdir -p "$(dirname "$OUTPUT_BASE")"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config_b64="$(gh api "repos/${REPO}/contents/.github/missions" --jq '.[].name' 2>/dev/null || echo "")"

if [ -z "$config_b64" ]; then
  # Fallback: try legacy single config
  config_b64="$(gh api "repos/${REPO}/contents/.github/pipeline-config.json" --jq '.content' | tr -d '\n')"
  printf '%s' "$config_b64" | base64 --decode > "$tmp_dir/pipeline-config.json"
  mission_configs=("$tmp_dir/pipeline-config.json")
else
  mkdir -p "$tmp_dir/missions"
  mission_configs=()
  for fname in $config_b64; do
    default_config="$tmp_dir/missions/default-${fname}"
    effective_config="$tmp_dir/missions/${fname}"
    file_b64="$(gh api "repos/${REPO}/contents/.github/missions/${fname}" --jq '.content' | tr -d '\n')"
    printf '%s' "$file_b64" | base64 --decode > "$default_config"

    mission_branch="$(jq -r '.mission.missionBranch // "main"' "$default_config")"
    branch_b64=""
    if [ -n "$mission_branch" ] && [ "$mission_branch" != "main" ]; then
      encoded_branch="$(jq -rn --arg ref "$mission_branch" '$ref | @uri')"
      if ! branch_b64="$(gh api "repos/${REPO}/contents/.github/missions/${fname}?ref=${encoded_branch}" --jq '.content' 2>/dev/null | tr -d '\n')"; then
        branch_b64=""
      fi
    fi

    if [ -n "$branch_b64" ]; then
      printf '%s' "$branch_b64" | base64 --decode > "$effective_config"
    else
      cp "$default_config" "$effective_config"
    fi

    mission_configs+=("$effective_config")
  done
fi

all_issue_ids=""
for mcfg in "${mission_configs[@]}"; do
  mcfg_issues="$((jq -r '.waves | to_entries[] | .value | if type == "object" then .issues[] else .[] end' "$mcfg" 2>/dev/null; jq -r '.waveGates | values[] // empty' "$mcfg" 2>/dev/null) | awk 'NF')"
  all_issue_ids="$(printf '%s\n%s' "$all_issue_ids" "$mcfg_issues")"
done
all_issue_ids="$(echo "$all_issue_ids" | awk 'NF' | sort -n | uniq)"

mkdir -p "$tmp_dir/issues"

for issue_id in $all_issue_ids; do
  gh issue view "$issue_id" -R "$REPO" --json number,state,title,labels,url,assignees,updatedAt > "$tmp_dir/issues/${issue_id}.json"
done

issues_json="$(jq -s '
  map({
    number,
    state,
    title,
    url,
    updatedAt,
    labels: [.labels[].name],
    assignees: [.assignees[].login],
    statusClass: (
      if .state == "CLOSED" then "done"
      elif ([.labels[].name] | index("status:in-progress")) then "inprogress"
      elif ([.labels[].name] | index("status:failed")) or ([.labels[].name] | index("needs-human")) then "failed"
      elif ([.labels[].name] | index("status:ready")) then "ready"
      elif ([.labels[].name] | index("status:blocked")) then "blocked"
      else "neutral"
      end
    )
  })
' "$tmp_dir/issues"/*.json)"

open_prs_json="$(gh pr list -R "$REPO" --state open --json number,title,author,isDraft,url,headRefName,baseRefName,updatedAt,mergeStateStatus,statusCheckRollup)"

declare -a workflow_files=(
  "assign-agent.yml"
  "wave-gate.yml"
  "on-issue-close.yml"
  "ci.yml"
)

declare -a workflow_labels=(
  "Assign Agent"
  "Wave Gate"
  "On Issue Close"
  "CI"
)

run_groups_payload='[]'
for idx in "${!workflow_files[@]}"; do
  wf_file="${workflow_files[$idx]}"
  wf_label="${workflow_labels[$idx]}"
  runs_json="$(gh run list -R "$REPO" --workflow "$wf_file" --limit 3 --json status,conclusion,event,headBranch,url,displayTitle,createdAt || echo '[]')"
  run_groups_payload="$(jq -c --arg wf "$wf_label" --argjson runs "$runs_json" '. + [{workflow: $wf, runs: $runs}]' <<< "$run_groups_payload")"
done

missions_json='[]'
for mcfg in "${mission_configs[@]}"; do
  mission_entry="$(jq -n \
    --argjson cfg "$(cat "$mcfg")" \
    --argjson issues "$issues_json" '
    {
      id: ($cfg.mission.id // "default"),
      name: ($cfg.mission.name // $cfg.mission.id // "default"),
      status: ($cfg.mission.status // "active"),
      baseBranch: ($cfg.mission.baseBranch // "main"),
      missionBranch: ($cfg.mission.missionBranch // "main"),
      waveGateRequired: ($cfg.autonomy.waveGateRequired // false),
      waves: (
        $cfg.waves
        | to_entries
        | sort_by(.key | tonumber)
        | map({
            id: (.key | tonumber),
            gateIssueId: ($cfg.waveGates[.key] // null),
            issues: [
              (.value | if type == "object" then .issues else . end)[] as $issueId
              | ($issues[] | select(.number == $issueId))
            ]
          })
      )
    }
  ')"
  missions_json="$(jq -c --argjson m "$mission_entry" '. + [$m]' <<< "$missions_json")"
done

final_json="$(jq -n \
  --arg repo "$REPO" \
  --arg generatedAt "$(date '+%Y-%m-%d %H:%M:%S %Z')" \
  --argjson missions "$missions_json" \
  --argjson openPrs "$open_prs_json" \
  --argjson runGroups "$run_groups_payload" '
  {
    repo: $repo,
    generatedAt: $generatedAt,
    missions: $missions,
    openPrs: $openPrs,
    recentRuns: $runGroups
  }
')"

printf '%s\n' "$final_json" > "$OUTPUT_JSON"

cat > "$OUTPUT_HTML" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mango Workflow Status</title>
  <style>
    :root {
      --mango-yellow: #ffce00;
      --mango-ink: #1a1a1a;
      --mango-bg: #f6f7f9;
      --mango-card: #ffffff;
      --mango-muted: #64748b;
      --state-done: #c8f7d0;
      --state-inprogress: #ffe58a;
      --state-ready: #cfe9ff;
      --state-blocked: #eceff3;
      --state-failed: #ffd3d3;
      --state-neutral: #efe7ff;
      --health-ok: #16a34a;
      --health-waiting: #ca8a04;
      --health-action: #dc2626;
      --health-blocked: #475569;
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
      background: linear-gradient(180deg, #fff7cc 0%, var(--mango-bg) 28%);
      color: var(--mango-ink);
    }
    .topbar {
      background: var(--mango-ink);
      color: white;
      border-bottom: 4px solid var(--mango-yellow);
      padding: 16px 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
    }
    .brand {
      font-weight: 800;
      letter-spacing: 0.6px;
    }
    .brand span {
      color: var(--mango-yellow);
    }
    .meta {
      font-size: 13px;
      color: #d1d5db;
      text-align: right;
    }
    .mode-banner {
      border: 1px solid #ead27a;
      background: linear-gradient(135deg, #fff9da 0%, #fff2bb 100%);
      color: #5b4800;
      border-radius: 12px;
      padding: 12px 14px;
      box-shadow: 0 10px 24px rgba(0,0,0,0.04);
      font-size: 13px;
      line-height: 1.5;
    }
    .mode-banner strong {
      color: #2d2300;
    }
    .mode-banner a {
      color: #2d2300;
      font-weight: 700;
    }
    .wrap {
      max-width: 1300px;
      margin: 18px auto 28px;
      padding: 0 16px;
      display: grid;
      gap: 16px;
    }
    .card {
      background: var(--mango-card);
      border: 1px solid #e5e7eb;
      border-radius: 14px;
      box-shadow: 0 10px 24px rgba(0,0,0,0.06);
      padding: 14px;
    }
    .section-title {
      margin: 0 0 10px;
      font-size: 16px;
      font-weight: 700;
    }
    .mission-control {
      display: grid;
      gap: 12px;
    }
    .mission-control-summary {
      padding: 12px 14px;
      border-radius: 12px;
      background: #111827;
      color: #f9fafb;
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      gap: 10px;
      align-items: center;
    }
    .mission-control-summary strong {
      color: var(--mango-yellow);
    }
    .mission-cards {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 12px;
    }
    .mission-card {
      border: 1px solid #e5e7eb;
      border-left-width: 6px;
      border-radius: 14px;
      background: #fff;
      padding: 14px;
      display: grid;
      gap: 10px;
    }
    .mission-card.ok { border-left-color: var(--health-ok); }
    .mission-card.waiting { border-left-color: var(--health-waiting); }
    .mission-card.action { border-left-color: var(--health-action); }
    .mission-card.blocked { border-left-color: var(--health-blocked); }
    .mission-card-head {
      display: flex;
      justify-content: space-between;
      gap: 8px;
      align-items: flex-start;
    }
    .mission-name {
      font-weight: 800;
      font-size: 16px;
      line-height: 1.2;
    }
    .health-pill {
      white-space: nowrap;
      border-radius: 999px;
      padding: 5px 9px;
      font-size: 12px;
      font-weight: 800;
      color: white;
    }
    .health-pill.ok { background: var(--health-ok); }
    .health-pill.waiting { background: var(--health-waiting); }
    .health-pill.action { background: var(--health-action); }
    .health-pill.blocked { background: var(--health-blocked); }
    .next-action {
      padding: 10px 12px;
      border-radius: 10px;
      background: #f8fafc;
      border: 1px solid #e5e7eb;
      font-size: 14px;
      line-height: 1.45;
    }
    .next-action strong { color: #111827; }
    .mission-facts {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }
    .fact {
      border-radius: 999px;
      border: 1px solid #e5e7eb;
      color: #475569;
      background: #f8fafc;
      padding: 4px 8px;
      font-size: 11px;
      font-weight: 700;
    }
    .mission-card a {
      color: #0f172a;
      font-weight: 700;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap: 10px;
    }
    .stat {
      padding: 10px 12px;
      border-radius: 10px;
      border: 1px solid #e5e7eb;
      background: #fcfcfd;
    }
    .stat b {
      display: block;
      font-size: 20px;
      margin-top: 4px;
    }
    .snapshot-story {
      margin: 0 0 12px;
      padding: 12px 14px;
      border-radius: 12px;
      border: 1px solid #e8e1bd;
      background: linear-gradient(180deg, #fffef6 0%, #fff9dc 100%);
      color: #4b5563;
      font-size: 14px;
      line-height: 1.5;
    }
    .snapshot-story strong {
      color: #111827;
    }
    .flow {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 12px;
    }
    .wave {
      border: 1px solid #e5e7eb;
      border-radius: 12px;
      background: #fff;
      overflow: hidden;
    }
    .wave-head {
      padding: 10px 12px;
      background: #fafafa;
      border-bottom: 1px solid #e5e7eb;
      font-weight: 700;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .chip {
      display: inline-block;
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      border: 1px solid rgba(0,0,0,0.08);
    }
    .issues {
      padding: 10px;
      display: grid;
      gap: 8px;
    }
    .issue {
      border-radius: 10px;
      padding: 9px;
      border: 1px solid rgba(0,0,0,0.06);
    }
    .issue a { color: inherit; text-decoration: none; }
    .issue a:hover { text-decoration: underline; }
    .issue .title {
      font-size: 13px;
      line-height: 1.25;
      margin-bottom: 4px;
      font-weight: 600;
    }
    .issue .sub {
      font-size: 11px;
      color: var(--mango-muted);
    }
    .done { background: var(--state-done); }
    .inprogress { background: var(--state-inprogress); }
    .ready { background: var(--state-ready); }
    .blocked { background: var(--state-blocked); }
    .failed { background: var(--state-failed); }
    .neutral { background: var(--state-neutral); }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      border-bottom: 1px solid #edf0f2;
      padding: 8px;
      text-align: left;
      vertical-align: top;
    }
    th { background: #fafafa; font-size: 12px; text-transform: uppercase; color: #475569; }
    .muted { color: var(--mango-muted); }
  </style>
</head>
<body>
  <div class="topbar">
    <div class="brand"><span>MANGO</span> Workflow Pulse</div>
    <div class="meta" id="meta"></div>
  </div>
  <div class="wrap">
    <div class="mode-banner" id="mode-banner"></div>

    <section class="card">
      <h2 class="section-title">Mission Control</h2>
      <div class="mission-control" id="mission-control"></div>
    </section>

    <section class="card">
      <h2 class="section-title">Snapshot</h2>
      <p class="snapshot-story" id="snapshot-story"></p>
      <div class="stats" id="stats"></div>
    </section>

    <section class="card">
      <h2 class="section-title">Wave Flow</h2>
      <div class="flow" id="flow"></div>
    </section>

    <section class="card">
      <h2 class="section-title">Open Pull Requests</h2>
      <div id="prs"></div>
    </section>

    <section class="card">
      <h2 class="section-title">Recent Workflow Runs</h2>
      <div id="runs"></div>
    </section>
  </div>

  <script id="workflow-data" type="application/json">
__JSON_PLACEHOLDER__
  </script>
  <script>
    const embeddedData = JSON.parse(document.getElementById('workflow-data').textContent);
    const liveUrl = 'http://localhost:4321';
    const liveDataUrl = `${liveUrl}/data.json`;
    const modeBanner = document.getElementById('mode-banner');
    const snapshotStoryEl = document.getElementById('snapshot-story');
    const metaEl = document.getElementById('meta');
    const missionControlEl = document.getElementById('mission-control');
    const statsEl = document.getElementById('stats');
    const flowEl = document.getElementById('flow');
    const prsEl = document.getElementById('prs');
    const runsEl = document.getElementById('runs');

    const getWaves = (data) => {
      if (Array.isArray(data.waves)) {
        return data.waves;
      }

      if (!Array.isArray(data.missions)) {
        return [];
      }

      return data.missions.flatMap((mission) => (mission.waves || []).map((wave) => ({
        ...wave,
        missionId: mission.id,
        missionName: mission.name || mission.id,
      })));
    };

    const checkSummary = (pr) => {
      const checks = pr.statusCheckRollup || [];
      const actionableChecks = checks.filter((check) => {
        const name = check.name || check.context || '';
        return name !== 'Vercel Preview Comments';
      });

      const failed = actionableChecks.filter((check) =>
        check.conclusion === 'FAILURE' ||
        check.conclusion === 'TIMED_OUT' ||
        check.conclusion === 'CANCELLED' ||
        check.conclusion === 'ACTION_REQUIRED' ||
        check.state === 'FAILURE' ||
        check.state === 'ERROR'
      );
      const pending = actionableChecks.filter((check) =>
        check.status && check.status !== 'COMPLETED' ||
        check.state === 'PENDING' ||
        check.state === 'EXPECTED'
      );
      const terminalOk = actionableChecks.filter((check) =>
        check.conclusion === 'SUCCESS' ||
        check.conclusion === 'SKIPPED' ||
        check.conclusion === 'NEUTRAL' ||
        check.state === 'SUCCESS'
      );
      const hasPositiveSignal = actionableChecks.some((check) =>
        check.conclusion === 'SUCCESS' || check.state === 'SUCCESS'
      );

      if (failed.length > 0) {
        return { state: 'failure', label: `${failed.length} check(s) fallando`, check: failed[0] };
      }

      if (pending.length > 0) {
        return { state: 'pending', label: `${pending.length} check(s) en curso`, check: pending[0] };
      }

      if (
        actionableChecks.length > 0 &&
        hasPositiveSignal &&
        terminalOk.length === actionableChecks.length
      ) {
        return { state: 'success', label: 'checks green' };
      }

      return { state: 'unknown', label: 'sin checks concluyentes' };
    };

    const missionPrs = (data, mission) => {
      const missionId = mission.id || 'default';
      return (data.openPrs || []).filter((pr) =>
        pr.baseRefName === mission.missionBranch ||
        pr.headRefName?.includes(missionId) ||
        pr.title?.includes(missionId)
      );
    };

    const findConsolidatedPr = (prs, missionId, waveId) =>
      prs.find((pr) =>
        pr.headRefName === `consolidate/${missionId}--wave-${waveId}` ||
        pr.headRefName === `wave-${waveId}/consolidate` ||
        pr.title?.includes(`wave-${waveId}`)
      );

    const findChildPrForIssue = (prs, issueNumber) =>
      prs.find((pr) =>
        !pr.headRefName?.startsWith('consolidate/') &&
        !pr.headRefName?.match(/^wave-\d+\/consolidate$/) &&
        (pr.title?.includes(`#${issueNumber}`) || false)
      );

    const currentWaveForMission = (mission, prs) => {
      const waves = mission.waves || [];
      const active = waves.find((wave) => {
        const issues = wave.issues || [];
        const hasOpenIssue = issues.some((issue) => issue.state !== 'CLOSED');
        const hasPr = Boolean(findConsolidatedPr(prs, mission.id, wave.id));
        return hasOpenIssue || hasPr;
      });

      return active || waves[waves.length - 1] || null;
    };

    const issueStats = (waves) => {
      const issues = (waves || []).flatMap((wave) => wave.issues || []);
      const count = (status) => issues.filter((issue) => issue.statusClass === status).length;
      return {
        total: issues.length,
        done: count('done'),
        failed: count('failed'),
        inprogress: count('inprogress'),
        ready: count('ready'),
        blocked: count('blocked'),
        open: issues.filter((issue) => issue.state !== 'CLOSED').length,
      };
    };

    const missionDiagnosis = (data, mission) => {
      const prs = missionPrs(data, mission);
      const stats = issueStats(mission.waves);
      const currentWave = currentWaveForMission(mission, prs);
      const currentIssues = currentWave?.issues || [];
      const consolidatedPr = currentWave ? findConsolidatedPr(prs, mission.id, currentWave.id) : null;
      const failedIssue = currentIssues.find((issue) => issue.statusClass === 'failed') ||
        (mission.waves || []).flatMap((wave) => wave.issues || []).find((issue) => issue.statusClass === 'failed');
      const readyIssue = currentIssues.find((issue) => issue.statusClass === 'ready');
      const inProgressIssue = currentIssues.find((issue) => issue.statusClass === 'inprogress');
      const blockedIssue = currentIssues.find((issue) => issue.statusClass === 'blocked');

      if (consolidatedPr) {
        const checks = checkSummary(consolidatedPr);
        if (checks.state === 'failure') {
          return {
            level: 'action',
            emoji: '🔴',
            status: 'Acción requerida',
            action: `CI fallando en PR #${consolidatedPr.number}: revisar o re-run para destrabar wave ${currentWave.id}.`,
            why: checks.label,
            link: consolidatedPr.url,
            linkText: `Abrir PR #${consolidatedPr.number}`,
            wave: currentWave,
            stats,
          };
        }

        if (checks.state === 'pending' || checks.state === 'unknown') {
          return {
            level: 'waiting',
            emoji: '🟡',
            status: 'Esperando CI',
            action: `No hacer nada todavía: esperar checks de PR #${consolidatedPr.number}.`,
            why: checks.label,
            link: consolidatedPr.url,
            linkText: `Ver PR #${consolidatedPr.number}`,
            wave: currentWave,
            stats,
          };
        }

        const nextWave = (mission.waves || []).find((wave) => Number(wave.id) === Number(currentWave.id) + 1);
        const reviewAction = nextWave
          ? `Revisar y mergear PR #${consolidatedPr.number} para avanzar a wave ${nextWave.id}.`
          : `Revisar y mergear PR #${consolidatedPr.number} para completar la misión.`;

        return {
          level: 'action',
          emoji: '🔴',
          status: 'Acción humana',
          action: reviewAction,
          why: 'La PR consolidada está lista; la automatización espera revisión/merge.',
          link: consolidatedPr.url,
          linkText: `Abrir PR #${consolidatedPr.number}`,
          wave: currentWave,
          stats,
        };
      }

      if (failedIssue) {
        return {
          level: 'action',
          emoji: '🔴',
          status: 'Acción requerida',
          action: `Revisar issue #${failedIssue.number}; quedó marcada como fallida o needs-human.`,
          why: 'La automatización no debería avanzar hasta resolver esa falla.',
          link: failedIssue.url,
          linkText: `Abrir issue #${failedIssue.number}`,
          wave: currentWave,
          stats,
        };
      }

      if (inProgressIssue) {
        return {
          level: 'waiting',
          emoji: '🟡',
          status: 'Agente trabajando',
          action: `No hacer nada: el agente trabaja en issue #${inProgressIssue.number}.`,
          why: 'Hay una tarea en progreso; esperar PR hija o actualización del agente.',
          link: inProgressIssue.url,
          linkText: `Ver issue #${inProgressIssue.number}`,
          wave: currentWave,
          stats,
        };
      }

      if (readyIssue) {
        return {
          level: 'waiting',
          emoji: '🟡',
          status: 'Esperando agente',
          action: `No hacer nada por ahora: issue #${readyIssue.number} está lista para asignación.`,
          why: 'Si sigue así más de ~30 min, conviene revisar Assign Agent.',
          link: readyIssue.url,
          linkText: `Ver issue #${readyIssue.number}`,
          wave: currentWave,
          stats,
        };
      }

      if (blockedIssue || stats.blocked > 0) {
        const issue = blockedIssue || (mission.waves || []).flatMap((wave) => wave.issues || []).find((item) => item.statusClass === 'blocked');
        return {
          level: 'blocked',
          emoji: '⚫',
          status: 'Bloqueada',
          action: issue ? `Esperando dependencia/gate en issue #${issue.number}.` : 'Esperando dependencias/gates.',
          why: 'No hay acción automática posible hasta que se desbloquee la dependencia.',
          link: issue?.url,
          linkText: issue ? `Ver issue #${issue.number}` : '',
          wave: currentWave,
          stats,
        };
      }

      if (stats.total > 0 && stats.done === stats.total) {
        return {
          level: 'ok',
          emoji: '🟢',
          status: 'Completa',
          action: 'No hacer nada: todas las issues de la misión están cerradas.',
          why: 'La misión no tiene trabajo pendiente en el dashboard.',
          wave: currentWave,
          stats,
        };
      }

      return {
        level: 'ok',
        emoji: '🟢',
        status: 'En orden',
        action: 'No hacer nada: no hay bloqueadores ni acciones humanas detectadas.',
        why: 'La misión está esperando el siguiente evento automático.',
        wave: currentWave,
        stats,
      };
    };

    const renderMissionControl = (data) => {
      const missions = data.missions || [{
        id: 'default',
        name: 'Default mission',
        missionBranch: 'main',
        waves: data.waves || [],
      }];
      const priority = { action: 0, blocked: 1, waiting: 2, ok: 3 };
      const diagnoses = missions.map((mission) => ({ mission, diagnosis: missionDiagnosis(data, mission) }));
      const sortedDiagnoses = [...diagnoses].sort((a, b) =>
        (priority[a.diagnosis.level] ?? 9) - (priority[b.diagnosis.level] ?? 9)
      );
      const firstAction = sortedDiagnoses.find((item) => item.diagnosis.level === 'action');
      const waiting = diagnoses.filter((item) => item.diagnosis.level === 'waiting').length;
      const blocked = diagnoses.filter((item) => item.diagnosis.level === 'blocked').length;

      const headline = firstAction
        ? `<strong>Qué tenés que hacer ahora:</strong> ${firstAction.diagnosis.action}`
        : blocked > 0
          ? `<strong>Atención:</strong> hay ${blocked} misión(es) bloqueada(s), pero sin PR lista para merge.`
          : waiting > 0
            ? `<strong>No hacer nada todavía:</strong> ${waiting} misión(es) están esperando CI/agente.`
            : '<strong>Todo en orden:</strong> no hay acciones humanas detectadas.';

      const cards = sortedDiagnoses.map(({ mission, diagnosis }) => {
        const waveText = diagnosis.wave ? `Wave ${diagnosis.wave.id}` : 'Sin wave';
        const link = diagnosis.link ? `<a href="${diagnosis.link}" target="_blank" rel="noreferrer">${diagnosis.linkText}</a>` : '';

        return `<article class="mission-card ${diagnosis.level}">
          <div class="mission-card-head">
            <div>
              <div class="mission-name">${mission.id}</div>
              <div class="muted">${mission.name || mission.id}</div>
            </div>
            <span class="health-pill ${diagnosis.level}">${diagnosis.emoji} ${diagnosis.status}</span>
          </div>
          <div class="next-action"><strong>Next action:</strong> ${diagnosis.action} ${link}</div>
          <div class="muted">${diagnosis.why}</div>
          <div class="mission-facts">
            <span class="fact">${waveText}</span>
            <span class="fact">${diagnosis.stats.done}/${diagnosis.stats.total} issues done</span>
            <span class="fact">${diagnosis.stats.inprogress} in progress</span>
            <span class="fact">${diagnosis.stats.blocked} blocked</span>
          </div>
        </article>`;
      }).join('');

      missionControlEl.innerHTML = `
        <div class="mission-control-summary">
          <div>${headline}</div>
          <div class="muted">${diagnoses.length} misión(es) monitoreadas</div>
        </div>
        <div class="mission-cards">${cards}</div>
      `;
    };

    const buildSnapshotStory = (data, metrics) => {
      if (Array.isArray(data.missions)) {
        const diagnoses = data.missions.map((mission) => missionDiagnosis(data, mission));
        const action = diagnoses.find((diagnosis) => diagnosis.level === 'action');
        const blocked = diagnoses.find((diagnosis) => diagnosis.level === 'blocked');
        const waitingCount = diagnoses.filter((diagnosis) => diagnosis.level === 'waiting').length;

        if (action) {
          return `<strong>Acción requerida:</strong> ${action.action}`;
        }

        if (blocked) {
          return `<strong>Bloqueado:</strong> ${blocked.action}`;
        }

        if (waitingCount > 0) {
          return `<strong>En espera:</strong> ${waitingCount} misión(es) esperan CI/agente. No hay acción humana inmediata.`;
        }
      }

      const latestConsolidatedPr = data.openPrs.find((pr) =>
        pr.headRefName?.startsWith('wave-') || pr.headRefName?.startsWith('consolidate/')
      );
      const waveFromRef = latestConsolidatedPr?.headRefName?.match(/wave-(\d+)/)?.[1];

      if (latestConsolidatedPr && waveFromRef) {
        const nextWave = Number(waveFromRef) + 1;
        return `Wave ${waveFromRef} está consolidada en el <strong>PR #${latestConsolidatedPr.number}</strong> y espera revisión manual; al mergearlo, se desbloquea la wave ${nextWave}.`;
      }

      if (metrics.failed > 0) {
        return `Hay <strong>${metrics.failed}</strong> items con fallas o bloqueo humano; el pipeline no puede avanzar hasta resolverlos.`;
      }

      if (metrics.inProgress > 0) {
        return `La wave activa sigue ejecutándose: <strong>${metrics.inProgress}</strong> issues están en progreso y hay <strong>${data.openPrs.length}</strong> PRs abiertos moviendo trabajo.`;
      }

      if (metrics.ready > 0 && metrics.blocked > 0) {
        return `Hay <strong>${metrics.ready}</strong> issues listos para agentes mientras <strong>${metrics.blocked}</strong> siguen bloqueados por dependencias o por un gate pendiente.`;
      }

      if (metrics.done === metrics.totalIssues && metrics.totalIssues > 0) {
        return 'La pipeline terminó: todas las waves quedaron completas y no hay trabajo pendiente.';
      }

      if (metrics.blocked > 0) {
        return `El pipeline está frenado por dependencias o gates: <strong>${metrics.blocked}</strong> issues siguen bloqueados antes de la próxima wave.`;
      }

      return 'El pipeline está esperando el próximo disparador automático o una revisión humana para avanzar.';
    };

    const renderModeBanner = (sourceMode, data) => {
      if (sourceMode === 'live-file-fetch') {
        modeBanner.innerHTML = `<strong>Snapshot con actualización automática.</strong> Abriste el archivo local, pero al cargar se trajeron datos vivos desde <a href="${liveUrl}">${liveUrl}</a>. Última generación: <strong>${data.generatedAt}</strong>.`;
        return;
      }

      if (sourceMode === 'file-loading') {
        modeBanner.innerHTML = `<strong>Snapshot estático.</strong> Intentando actualizar automáticamente desde <a href="${liveUrl}">${liveUrl}</a> al abrir la página.`;
        return;
      }

      if (sourceMode === 'file-fallback') {
        modeBanner.innerHTML = `<strong>Snapshot estático.</strong> No se pudo consultar <a href="${liveUrl}">${liveUrl}</a> al cargar la página, así que estás viendo el estado guardado en <strong>${data.generatedAt}</strong>.`;
        return;
      }

      modeBanner.innerHTML = `<strong>Vista live.</strong> Cada recarga vuelve a generar el estado desde GitHub. Última generación: <strong>${data.generatedAt}</strong>.`;
    };

    const renderPage = (data, sourceMode) => {
      const waves = getWaves(data);
      const allIssues = waves.flatMap((wave) => wave.issues || []);
      const countByStatus = (status) => allIssues.filter((issue) => issue.statusClass === status).length;
      const metrics = {
        totalIssues: allIssues.length,
        inProgress: countByStatus('inprogress'),
        ready: countByStatus('ready'),
        blocked: countByStatus('blocked'),
        failed: countByStatus('failed'),
        done: countByStatus('done'),
      };

      renderModeBanner(sourceMode, data);
      renderMissionControl(data);
      snapshotStoryEl.innerHTML = buildSnapshotStory(data, metrics);
      metaEl.innerHTML = `${data.repo}<br><span class="muted">Updated ${data.generatedAt}</span>`;

      const stats = [
        ['Missions', data.missions?.length || 1],
        ['Waves', waves.length],
        ['Total Issues', metrics.totalIssues],
        ['In Progress', metrics.inProgress],
        ['Ready', metrics.ready],
        ['Blocked', metrics.blocked],
        ['Done', metrics.done],
        ['Open PRs', data.openPrs.length],
      ];
      statsEl.innerHTML = stats.map(([k,v]) => `<div class="stat"><div class="muted">${k}</div><b>${v}</b></div>`).join('');

      flowEl.innerHTML = waves.map((wave) => {
      const gate = wave.gateIssueId ? `<span class="chip">Gate #${wave.gateIssueId}</span>` : '<span class="chip">No gate</span>';
      const issues = (wave.issues || []).map((issue) => {
        return `<div class="issue ${issue.statusClass}">
          <a href="${issue.url}" target="_blank" rel="noreferrer">
            <div class="title">#${issue.number} ${issue.title}</div>
          </a>
          <div class="sub">${issue.state} · ${issue.assignees.join(', ') || 'No assignee'}</div>
        </div>`;
      }).join('');
      return `<div class="wave">
        <div class="wave-head">${wave.missionId ? `${wave.missionId} · ` : ''}Wave ${wave.id}${gate}</div>
        <div class="issues">${issues}</div>
      </div>`;
    }).join('');

      if (data.openPrs.length === 0) {
        prsEl.innerHTML = '<p class="muted">No open PRs.</p>';
      } else {
      const prRows = data.openPrs.map((pr) => `
        <tr>
          <td>#${pr.number}</td>
          <td><a href="${pr.url}" target="_blank" rel="noreferrer">${pr.title}</a></td>
          <td>${pr.author.login}</td>
          <td>${pr.isDraft ? 'Yes' : 'No'}</td>
          <td>${pr.headRefName} -> ${pr.baseRefName}</td>
        </tr>`).join('');
        prsEl.innerHTML = `<table>
        <thead><tr><th>PR</th><th>Title</th><th>Author</th><th>Draft</th><th>Branch</th></tr></thead>
        <tbody>${prRows}</tbody>
      </table>`;
      }

      const runRows = data.recentRuns.flatMap((group) => group.runs.map((run) => ({...run, workflow: group.workflow})));
      if (runRows.length === 0) {
        runsEl.innerHTML = '<p class="muted">No runs available.</p>';
      } else {
        runsEl.innerHTML = `<table>
        <thead><tr><th>Workflow</th><th>Status</th><th>Conclusion</th><th>Event</th><th>Branch</th><th>When</th></tr></thead>
        <tbody>
          ${runRows.map((run) => `
            <tr>
              <td><a href="${run.url}" target="_blank" rel="noreferrer">${run.workflow}</a></td>
              <td>${run.status}</td>
              <td>${run.conclusion || '-'}</td>
              <td>${run.event}</td>
              <td>${run.headBranch || '-'}</td>
              <td>${new Date(run.createdAt).toLocaleString()}</td>
            </tr>`).join('')}
        </tbody>
      </table>`;
      }
    };

    const loadLiveDataFromFile = async () => {
      renderPage(embeddedData, 'file-loading');

      const controller = new AbortController();
      const timeoutId = window.setTimeout(() => controller.abort(), 4000);

      try {
        const response = await fetch(`${liveDataUrl}?ts=${Date.now()}`, {
          cache: 'no-store',
          signal: controller.signal,
        });

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }

        const liveData = await response.json();
        renderPage(liveData, 'live-file-fetch');
      } catch (_) {
        renderPage(embeddedData, 'file-fallback');
      } finally {
        window.clearTimeout(timeoutId);
      }
    };

    if (window.location.protocol === 'file:') {
      loadLiveDataFromFile();
    } else {
      renderPage(embeddedData, 'live-server-page');
    }
  </script>
</body>
</html>
HTML

awk -v json_file="$OUTPUT_JSON" '
  /__JSON_PLACEHOLDER__/ {
    while ((getline line < json_file) > 0) {
      print line
    }
    close(json_file)
    next
  }
  { print }
' "$OUTPUT_HTML" > "$OUTPUT_HTML.tmp"
mv "$OUTPUT_HTML.tmp" "$OUTPUT_HTML"

echo "Generated ${OUTPUT_JSON}"
echo "Generated ${OUTPUT_HTML}"
