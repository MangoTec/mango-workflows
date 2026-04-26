#!/usr/bin/env node

// Local dev server for the pipeline status page.
// Regenerates HTML on every browser request — no stale data.
//
// Usage:
//   node scripts/serve-status.js [repo] [port]
//   node scripts/serve-status.js MangoTec/mango-portal 4321
//
// Or via npm script: npm run status

const http = require('node:http');
const { execSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const REPO  = process.argv[2] || 'MangoTec/mango-portal';
const PORT  = Number(process.argv[3]) || 4321;
const ROOT  = path.resolve(__dirname, '..');
const GEN   = path.join(ROOT, 'scripts', 'generate-workflow-graph.sh');
const OUT   = path.join(ROOT, 'status', 'mango-portal');

function regenerate() {
  console.log(`[${new Date().toISOString()}] Regenerating status for ${REPO}…`);
  const result = spawnSync('bash', [GEN, REPO, OUT], {
    cwd: ROOT,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env },
  });

  if (result.status !== 0) {
    const err = result.stderr?.toString() || result.stdout?.toString() || 'unknown error';
    console.error('Generator failed:', err.trim());
    return null;
  }

  const htmlPath = `${OUT}.html`;
  const jsonPath = `${OUT}.json`;
  if (!fs.existsSync(htmlPath)) {
    console.error('HTML file not found after generation:', htmlPath);
    return null;
  }

  if (!fs.existsSync(jsonPath)) {
    console.error('JSON file not found after generation:', jsonPath);
    return null;
  }

  return {
    html: fs.readFileSync(htmlPath, 'utf8'),
    json: fs.readFileSync(jsonPath, 'utf8'),
  };
}

const server = http.createServer((req, res) => {
  const requestUrl = new URL(req.url || '/', 'http://127.0.0.1');

  // Ignore favicon
  if (requestUrl.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }

  const payload = regenerate();

  if (!payload) {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end('Failed to generate status page. Check terminal for errors.');
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
  console.log(`   Refreshes live data on every page load\n`);

  // Open browser automatically
  try {
    execSync(`open "${url}"`, { stdio: 'ignore' });
  } catch (_) {
    // Not on macOS or open not available — user opens manually
  }
});
