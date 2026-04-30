#!/usr/bin/env node

// Local dev server for the pipeline status page.
// Serves the last generated snapshot immediately and refreshes GitHub data in
// the background on browser requests. This keeps localhost responsive even when
// the GitHub CLI or API is slow.
//
// Usage:
//   node scripts/serve-status.js [repo] [port] [--no-open]
//   node scripts/serve-status.js MangoTec/mango-portal 4321
//   node scripts/serve-status.js MangoTec/mango-app-v2 4321 --no-open
//
// Or via npm script: npm run status

const http = require('node:http');
const { execSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const args = process.argv.slice(2);
const REPO = args.find((arg) => !arg.startsWith('--')) || 'MangoTec/mango-portal';
const portArg = args.find((arg) => /^\d+$/.test(arg));
const PORT = Number(portArg) || 4321;
const NO_OPEN =
  args.includes('--no-open') ||
  ['1', 'true', 'yes'].includes(String(process.env.MANGO_WORKFLOW_VIEWER_NO_OPEN || '').toLowerCase());
const ROOT = path.resolve(__dirname, '..');
const GEN = path.join(ROOT, 'scripts', 'generate-workflow-graph.sh');
const OUT = process.env.MANGO_WORKFLOW_VIEWER_OUTPUT_BASE
  ? path.resolve(process.env.MANGO_WORKFLOW_VIEWER_OUTPUT_BASE)
  : path.join(ROOT, 'status', 'mango-portal');
const REFRESH_TIMEOUT_MS = Number(process.env.MANGO_WORKFLOW_VIEWER_REFRESH_TIMEOUT_MS || 180_000);
const MIN_REFRESH_INTERVAL_MS = Number(process.env.MANGO_WORKFLOW_VIEWER_MIN_REFRESH_INTERVAL_MS || 5_000);

let refreshInProgress = false;
let lastRefreshStartedAt = 0;
let lastRefreshFinishedAt = 0;
let lastRefreshError = '';

function readSnapshot() {
  const htmlPath = `${OUT}.html`;
  const jsonPath = `${OUT}.json`;
  if (!fs.existsSync(htmlPath) || !fs.existsSync(jsonPath)) {
    return null;
  }

  return {
    html: fs.readFileSync(htmlPath, 'utf8'),
    json: fs.readFileSync(jsonPath, 'utf8'),
  };
}

function triggerRefresh(reason = 'request') {
  const now = Date.now();

  if (refreshInProgress) {
    return false;
  }

  if (now - lastRefreshStartedAt < MIN_REFRESH_INTERVAL_MS) {
    return false;
  }

  refreshInProgress = true;
  lastRefreshStartedAt = now;
  lastRefreshError = '';

  console.log(`[${new Date().toISOString()}] Regenerating status for ${REPO} (${reason})…`);
  const child = spawn('bash', [GEN, REPO, OUT], {
    cwd: ROOT,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env },
  });

  let stdout = '';
  let stderr = '';
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill('SIGTERM');
    setTimeout(() => child.kill('SIGKILL'), 5_000).unref();
  }, REFRESH_TIMEOUT_MS);
  timer.unref();

  child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
  child.on('close', (code, signal) => {
    clearTimeout(timer);
    refreshInProgress = false;
    lastRefreshFinishedAt = Date.now();

    if (code === 0 && !timedOut) {
      console.log(`[${new Date().toISOString()}] Status regenerated for ${REPO}`);
      if (stdout.trim()) console.log(stdout.trim());
      return;
    }

    lastRefreshError = timedOut
      ? `Generator timed out after ${REFRESH_TIMEOUT_MS}ms`
      : `Generator exited with code=${code} signal=${signal || ''}`;

    console.error(lastRefreshError);
    const details = stderr.trim() || stdout.trim();
    if (details) console.error(details.slice(-4000));
  });

  child.on('error', (error) => {
    clearTimeout(timer);
    refreshInProgress = false;
    lastRefreshFinishedAt = Date.now();
    lastRefreshError = error.message;
    console.error('Generator failed:', error);
  });

  return true;
}

function loadingPage() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mango Workflow Status</title>
  <meta http-equiv="refresh" content="5" />
  <style>
    body { margin: 0; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #fff7cc; color: #111827; }
    main { max-width: 760px; margin: 15vh auto; background: white; border: 1px solid #e5e7eb; border-radius: 16px; padding: 24px; box-shadow: 0 10px 24px rgba(0,0,0,.08); }
    h1 { margin-top: 0; }
    code { background: #f3f4f6; padding: 2px 5px; border-radius: 6px; }
  </style>
</head>
<body>
  <main>
    <h1>Mango Workflow Pulse</h1>
    <p>Estoy generando el primer snapshot para <code>${REPO}</code>.</p>
    <p>La página se recarga sola en unos segundos. Después de esto, el viewer sirve el último snapshot al instante y refresca GitHub en background.</p>
  </main>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const requestUrl = new URL(req.url || '/', 'http://127.0.0.1');

  // Ignore favicon
  if (requestUrl.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }

  if (requestUrl.pathname === '/healthz') {
    res.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; charset=utf-8',
    });
    res.end(`ok ${refreshInProgress ? 'refreshing' : 'idle'}\n`);
    return;
  }

  if (requestUrl.pathname === '/service-status.json') {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    });
    res.end(JSON.stringify({
      repo: REPO,
      outputBase: OUT,
      refreshInProgress,
      lastRefreshStartedAt,
      lastRefreshFinishedAt,
      lastRefreshError,
      hasSnapshot: Boolean(readSnapshot()),
    }, null, 2));
    return;
  }

  const forceRefresh = requestUrl.pathname === '/refresh' || requestUrl.searchParams.get('refresh') === '1';
  triggerRefresh(forceRefresh ? 'manual-refresh' : 'request');

  const payload = readSnapshot();
  if (!payload) {
    res.writeHead(202, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/html; charset=utf-8',
    });
    res.end(loadingPage());
    return;
  }

  if (requestUrl.pathname === '/data.json') {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    });
    res.end(payload.json);
    return;
  }

  res.writeHead(200, {
    'Cache-Control': 'no-store',
    'Content-Type': 'text/html; charset=utf-8',
  });
  res.end(payload.html);
});

server.listen(PORT, '127.0.0.1', () => {
  const url = `http://localhost:${PORT}`;
  console.log(`✅ Status server running → ${url}`);
  console.log(`   Repo: ${REPO}`);
  console.log(`   Output: ${OUT}.html`);
  console.log(`   Refreshes live data on every page load\n`);

  if (!NO_OPEN) {
    // Open browser automatically for interactive local runs.
    // LaunchAgent/service runs should pass --no-open.
    try {
      execSync(`open "${url}"`, { stdio: 'ignore' });
    } catch (_) {
      // Not on macOS or open not available — user opens manually
    }
  }
});
