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
    file_b64="$(gh api "repos/${REPO}/contents/.github/missions/${fname}" --jq '.content' | tr -d '\n')"
    printf '%s' "$file_b64" | base64 --decode > "$tmp_dir/missions/${fname}"
    mission_configs+=("$tmp_dir/missions/${fname}")
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
  gh issue view "$issue_id" -R "$REPO" --json number,state,title,labels,url,assignees > "$tmp_dir/issues/${issue_id}.json"
done

issues_json="$(jq -s '
  map({
    number,
    state,
    title,
    url,
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

open_prs_json="$(gh pr list -R "$REPO" --state open --json number,title,author,isDraft,url,headRefName,baseRefName)"

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
    const statsEl = document.getElementById('stats');
    const flowEl = document.getElementById('flow');
    const prsEl = document.getElementById('prs');
    const runsEl = document.getElementById('runs');

    const buildSnapshotStory = (data, metrics) => {
      const latestConsolidatedPr = data.openPrs.find((pr) => pr.headRefName?.startsWith('wave-'));
      const waveFromRef = latestConsolidatedPr?.headRefName?.match(/^wave-(\d+)/)?.[1];

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
      const allIssues = data.waves.flatMap((wave) => wave.issues);
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
      snapshotStoryEl.innerHTML = buildSnapshotStory(data, metrics);
      metaEl.innerHTML = `${data.repo}<br><span class="muted">Updated ${data.generatedAt}</span>`;

      const stats = [
        ['Total Issues', metrics.totalIssues],
        ['In Progress', metrics.inProgress],
        ['Ready', metrics.ready],
        ['Blocked', metrics.blocked],
        ['Done', metrics.done],
        ['Open PRs', data.openPrs.length],
      ];
      statsEl.innerHTML = stats.map(([k,v]) => `<div class="stat"><div class="muted">${k}</div><b>${v}</b></div>`).join('');

      flowEl.innerHTML = data.waves.map((wave) => {
      const gate = wave.gateIssueId ? `<span class="chip">Gate #${wave.gateIssueId}</span>` : '<span class="chip">No gate</span>';
      const issues = wave.issues.map((issue) => {
        return `<div class="issue ${issue.statusClass}">
          <a href="${issue.url}" target="_blank" rel="noreferrer">
            <div class="title">#${issue.number} ${issue.title}</div>
          </a>
          <div class="sub">${issue.state} · ${issue.assignees.join(', ') || 'No assignee'}</div>
        </div>`;
      }).join('');
      return `<div class="wave">
        <div class="wave-head">Wave ${wave.id}${gate}</div>
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
