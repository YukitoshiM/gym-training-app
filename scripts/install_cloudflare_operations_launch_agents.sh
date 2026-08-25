#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/Library/Logs/BodyMode"
REPORT_DIR="${HOME}/Library/Application Support/BodyMode/operations"
RUNTIME_DIR="${REPORT_DIR}/runtime"
BACKUP_SCRIPT="${RUNTIME_DIR}/scripts/backup_cloudflare_backend.sh"
REPORT_SCRIPT="${RUNTIME_DIR}/scripts/cloudflare_operations_report.py"
MONITOR_SCRIPT="${RUNTIME_DIR}/scripts/cloudflare_operations_monitor.py"

mkdir -p "${AGENTS_DIR}" "${LOG_DIR}" "${REPORT_DIR}" \
  "${RUNTIME_DIR}/scripts" "${RUNTIME_DIR}/cloudflare_ai_gateway"
install -m 700 "${ROOT_DIR}/scripts/backup_cloudflare_backend.sh" "${BACKUP_SCRIPT}"
install -m 700 "${ROOT_DIR}/scripts/cloudflare_operations_report.py" "${REPORT_SCRIPT}"
install -m 700 "${ROOT_DIR}/scripts/cloudflare_operations_monitor.py" "${MONITOR_SCRIPT}"
install -m 600 "${ROOT_DIR}/cloudflare_ai_gateway/wrangler.jsonc" \
  "${RUNTIME_DIR}/cloudflare_ai_gateway/wrangler.jsonc"

cat > "${AGENTS_DIR}/com.bodymode.operations-report.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.bodymode.operations-report</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/python3</string><string>${MONITOR_SCRIPT}</string>
    <string>--report-script</string><string>${REPORT_SCRIPT}</string>
    <string>--report-output</string><string>${REPORT_DIR}/latest.json</string>
    <string>--state-file</string><string>${REPORT_DIR}/monitor-state.json</string>
  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/operations-report.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/operations-report-error.log</string>
</dict></plist>
PLIST

cat > "${AGENTS_DIR}/com.bodymode.cloudflare-backup.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.bodymode.cloudflare-backup</string>
  <key>ProgramArguments</key><array>
    <string>${BACKUP_SCRIPT}</string><string>--retention-days</string><string>14</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>20</integer></dict>
  <key>StandardOutPath</key><string>${LOG_DIR}/cloudflare-backup.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/cloudflare-backup-error.log</string>
</dict></plist>
PLIST

for label in com.bodymode.operations-report com.bodymode.cloudflare-backup; do
  launchctl bootout "gui/${UID}/${label}" 2>/dev/null || true
  launchctl bootstrap "gui/${UID}" "${AGENTS_DIR}/${label}.plist"
done

printf 'Installed hourly operations monitoring with notifications and daily Cloudflare backup.\n'
