#!/usr/bin/env bash

set -euo pipefail

LABEL="${MANGO_WORKFLOW_VIEWER_LABEL:-com.mangotec.workflow-viewer}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_VALUE="$(id -u)"

launchctl bootout "gui/${UID_VALUE}" "$PLIST" >/dev/null 2>&1 || true
launchctl disable "gui/${UID_VALUE}/${LABEL}" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "✅ Mango workflow viewer uninstalled"
echo "   Removed: ${PLIST}"
