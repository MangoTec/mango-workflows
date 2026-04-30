#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${MANGO_WORKFLOW_VIEWER_LABEL:-com.mangotec.workflow-viewer}"
REPO="${1:-MangoTec/mango-app-v2}"
PORT="${2:-4321}"
NODE_BIN="${NODE_BIN:-$(command -v node)}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs"
UID_VALUE="$(id -u)"

mkdir -p "${HOME}/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${ROOT}/scripts/serve-status.js</string>
    <string>${REPO}</string>
    <string>${PORT}</string>
    <string>--no-open</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${ROOT}</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>MANGO_WORKFLOW_VIEWER_NO_OPEN</key>
    <string>1</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${LOG_DIR}/mango-workflow-viewer.log</string>

  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/mango-workflow-viewer.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/${UID_VALUE}" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${UID_VALUE}" "$PLIST"
launchctl enable "gui/${UID_VALUE}/${LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/${UID_VALUE}/${LABEL}"

echo "✅ Mango workflow viewer installed"
echo "   URL: http://localhost:${PORT}"
echo "   Repo: ${REPO}"
echo "   Plist: ${PLIST}"
echo "   Logs: ${LOG_DIR}/mango-workflow-viewer.log"
