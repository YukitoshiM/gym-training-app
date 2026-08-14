#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SOURCE_DIR="${REPO_ROOT}/local_llm_server"
INSTALL_DIR="${HOME}/Library/Application Support/BodyMode/local_ai_server"
SERVER_RUNNER="${INSTALL_DIR}/run_server.sh"
LABEL="com.yukitoshim.gymtraining.local-llm"
MONITOR_LABEL="com.yukitoshim.gymtraining.local-llm-monitor"
EVIDENCE_LABEL="com.yukitoshim.gymtraining.evidence-sync"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
MONITOR_PLIST_PATH="${HOME}/Library/LaunchAgents/${MONITOR_LABEL}.plist"
EVIDENCE_PLIST_PATH="${HOME}/Library/LaunchAgents/${EVIDENCE_LABEL}.plist"
MONITOR_SCRIPT="${REPO_ROOT}/scripts/check_local_ai_health.sh"
INSTALLED_MONITOR_SCRIPT="${INSTALL_DIR}/check_local_ai_health.sh"
LOG_DIR="${HOME}/Library/Logs/BodyMode"
DOMAIN="gui/${UID}"

bootstrap_agent() {
  local plist_path="$1"

  if launchctl bootstrap "${DOMAIN}" "${plist_path}"; then
    return 0
  fi
  sleep 1
  launchctl bootstrap "${DOMAIN}" "${plist_path}"
}

if [[ ! -x "${SOURCE_DIR}/run_server.sh" ]]; then
  print -u2 "Server runner is not executable: ${SOURCE_DIR}/run_server.sh"
  exit 1
fi

if [[ ! -x "${SOURCE_DIR}/.venv/bin/python" ]]; then
  print -u2 "Create local_llm_server/.venv and install requirements first"
  exit 1
fi

if ! "${SOURCE_DIR}/.venv/bin/python" - <<'PY'
import sqlite3
import sqlite_vec

connection = sqlite3.connect(":memory:")
if not hasattr(connection, "enable_load_extension"):
    raise SystemExit(1)
connection.enable_load_extension(True)
sqlite_vec.load(connection)
connection.enable_load_extension(False)
connection.execute("SELECT vec_version()").fetchone()
PY
then
  print -u2 "Python environment cannot load sqlite-vec; run local_llm_server/setup_environment.sh"
  exit 1
fi

if [[ ! -s "${SOURCE_DIR}/.api_key" ]]; then
  print -u2 "Create local_llm_server/.api_key with a non-development API key first"
  exit 1
fi

mkdir -p "${HOME}/Library/LaunchAgents" "${LOG_DIR}" "${INSTALL_DIR}"
launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
launchctl bootout "${DOMAIN}/${MONITOR_LABEL}" 2>/dev/null || true
launchctl bootout "${DOMAIN}/${EVIDENCE_LABEL}" 2>/dev/null || true
rm -f "${PLIST_PATH}"
rm -f "${MONITOR_PLIST_PATH}"
rm -f "${EVIDENCE_PLIST_PATH}"

# Background agents cannot reliably read scripts under macOS-protected Documents.
# Install an owned runtime copy in Application Support instead of using /tmp.
rsync -a --delete \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "${SOURCE_DIR}/" "${INSTALL_DIR}/"
chmod 700 "${SERVER_RUNNER}"
chmod 700 "${INSTALL_DIR}/sync_evidence.sh"
chmod 600 "${INSTALL_DIR}/.api_key"
install -m 700 "${MONITOR_SCRIPT}" "${INSTALLED_MONITOR_SCRIPT}"
if [[ -f "${INSTALL_DIR}/.health_enrollment_key" ]]; then
  chmod 600 "${INSTALL_DIR}/.health_enrollment_key"
fi
if [[ -f "${INSTALL_DIR}/.public_base_url" ]]; then
  chmod 600 "${INSTALL_DIR}/.public_base_url"
fi

SOURCE_MONITOR_HASH=$(shasum -a 256 "${MONITOR_SCRIPT}" | awk '{print $1}')
INSTALLED_MONITOR_HASH=$(shasum -a 256 "${INSTALLED_MONITOR_SCRIPT}" | awk '{print $1}')
if [[ "${SOURCE_MONITOR_HASH}" != "${INSTALLED_MONITOR_HASH}" ]]; then
  print -u2 "Installed health monitor does not match the repository copy"
  exit 1
fi

plutil -create xml1 "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :Label string ${LABEL}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${SERVER_RUNNER}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :KeepAlive dict" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :KeepAlive:SuccessfulExit bool false" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ThrottleInterval integer 10" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string ${LOG_DIR}/local-ai.log" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string ${LOG_DIR}/local-ai.error.log" "${PLIST_PATH}"
chmod 600 "${PLIST_PATH}"

plutil -create xml1 "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :Label string ${MONITOR_LABEL}" "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${INSTALLED_MONITOR_SCRIPT}" "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StartInterval integer 60" "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string ${LOG_DIR}/local-ai-monitor.log" "${MONITOR_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string ${LOG_DIR}/local-ai-monitor.log" "${MONITOR_PLIST_PATH}"
chmod 600 "${MONITOR_PLIST_PATH}"

plutil -create xml1 "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :Label string ${EVIDENCE_LABEL}" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${INSTALL_DIR}/sync_evidence.sh" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string --limit-per-query" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string 160" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StartCalendarInterval dict" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Weekday integer 2" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Hour integer 3" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Minute integer 15" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ThrottleInterval integer 300" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string ${LOG_DIR}/evidence-sync.log" "${EVIDENCE_PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string ${LOG_DIR}/evidence-sync.error.log" "${EVIDENCE_PLIST_PATH}"
chmod 600 "${EVIDENCE_PLIST_PATH}"

PLIST_MONITOR_SCRIPT=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "${MONITOR_PLIST_PATH}")
if [[ "${PLIST_MONITOR_SCRIPT}" != "${INSTALLED_MONITOR_SCRIPT}" ]]; then
  print -u2 "Monitor LaunchAgent references an unexpected script: ${PLIST_MONITOR_SCRIPT}"
  exit 1
fi

bootstrap_agent "${PLIST_PATH}"
bootstrap_agent "${MONITOR_PLIST_PATH}"
bootstrap_agent "${EVIDENCE_PLIST_PATH}"
launchctl kickstart -k "${DOMAIN}/${LABEL}"

print "Installed ${LABEL}"
print "Runtime: ${INSTALL_DIR}"
print "Logs: ${LOG_DIR}/local-ai.log and ${LOG_DIR}/local-ai.error.log"
print "Evidence sync: every Monday at 03:15 (${LOG_DIR}/evidence-sync.log)"
print "Health monitor SHA-256: ${INSTALLED_MONITOR_HASH}"
