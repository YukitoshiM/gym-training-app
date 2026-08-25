#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LABEL="com.yukitoshim.gymtraining.local-llm"
DOMAIN="gui/${UID}"
STATE_DIR="${HOME}/Library/Application Support/BodyMode/monitor"
FAILURE_FILE="${STATE_DIR}/local-ai-consecutive-failures"
INFERENCE_FAILURE_FILE="${STATE_DIR}/local-ai-inference-consecutive-failures"
LOG_DIR="${HOME}/Library/Logs/BodyMode"
MAX_LOG_BYTES=$((5 * 1024 * 1024))
MAX_LOG_AGE_SECONDS=$((14 * 24 * 60 * 60))
LOCAL_BASE_URL="${BODYMODE_AI_LOCAL_BASE_URL:-http://127.0.0.1:8765}"
PUBLIC_URL_FILE="${BODYMODE_AI_PUBLIC_BASE_URL_FILE:-${SCRIPT_DIR}/.public_base_url}"
CREDENTIAL_FILE="${BODYMODE_AI_HEALTH_CREDENTIAL_FILE:-${SCRIPT_DIR}/.health_enrollment_key}"
GATEWAY_KEY_FILE="${BODYMODE_AI_GATEWAY_KEY_FILE:-${SCRIPT_DIR}/.gateway_shared_secret}"
CURL_TIMEOUT="${BODYMODE_AI_HEALTH_TIMEOUT_SECONDS:-12}"
PUBLIC_HEALTH_ATTEMPTS="${BODYMODE_AI_PUBLIC_HEALTH_ATTEMPTS:-3}"
PUBLIC_HEALTH_INITIAL_BACKOFF_SECONDS="${BODYMODE_AI_PUBLIC_HEALTH_INITIAL_BACKOFF_SECONDS:-1}"
PUBLIC_RECOVERY_THRESHOLD="${BODYMODE_AI_PUBLIC_RECOVERY_THRESHOLD:-3}"
INFERENCE_RECOVERY_THRESHOLD="${BODYMODE_AI_INFERENCE_RECOVERY_THRESHOLD:-3}"
TAILSCALE_SOCKET="${BODYMODE_TAILSCALE_SOCKET:-${HOME}/Library/Application Support/BodyMode/tailscale/tailscaled.socket}"
TAILSCALE_BIN="${BODYMODE_TAILSCALE_BIN:-/opt/homebrew/bin/tailscale}"

if [[ ! -r "${CREDENTIAL_FILE}" && -r "${HOME}/Library/Application Support/BodyMode/local_ai_server/.health_enrollment_key" ]]; then
  CREDENTIAL_FILE="${HOME}/Library/Application Support/BodyMode/local_ai_server/.health_enrollment_key"
elif [[ ! -r "${CREDENTIAL_FILE}" ]]; then
  CREDENTIAL_FILE="${SCRIPT_DIR}/.api_key"
fi
if [[ ! -r "${GATEWAY_KEY_FILE}" && -r "${HOME}/Library/Application Support/BodyMode/local_ai_server/.gateway_shared_secret" ]]; then
  GATEWAY_KEY_FILE="${HOME}/Library/Application Support/BodyMode/local_ai_server/.gateway_shared_secret"
fi

PUBLIC_BASE_URL="${BODYMODE_AI_PUBLIC_BASE_URL:-}"
if [[ -z "${PUBLIC_BASE_URL}" && -r "${PUBLIC_URL_FILE}" ]]; then
  PUBLIC_BASE_URL="$(tr -d '\r\n' < "${PUBLIC_URL_FILE}")"
fi
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
LOCAL_BASE_URL="${LOCAL_BASE_URL%/}"

if [[ -x "${SCRIPT_DIR}/.venv/bin/python" ]]; then
  PYTHON="${SCRIPT_DIR}/.venv/bin/python"
else
  PYTHON="$(command -v python3 || true)"
fi

mkdir -p "${STATE_DIR}" "${LOG_DIR}"

now_epoch=$(date +%s)
server_log_rotated=false
for log in "${LOG_DIR}/local-ai.log" "${LOG_DIR}/local-ai.error.log"; do
  [[ -f "${log}" ]] || continue
  size=$(stat -f %z "${log}")
  created_at=$(stat -f %B "${log}")
  age=$((now_epoch - created_at))
  if (( size > MAX_LOG_BYTES || age > MAX_LOG_AGE_SECONDS )); then
    mv -f "${log}" "${log}.1"
    : > "${log}"
    server_log_rotated=true
  fi
  find "${log}.1" -mtime +14 -delete 2>/dev/null || true
done

monitor_log="${LOG_DIR}/local-ai-monitor.log"
if [[ -f "${monitor_log}" ]]; then
  size=$(stat -f %z "${monitor_log}")
  created_at=$(stat -f %B "${monitor_log}")
  age=$((now_epoch - created_at))
  if (( size > MAX_LOG_BYTES || age > MAX_LOG_AGE_SECONDS )); then
    mv -f "${monitor_log}" "${monitor_log}.1"
    : > "${monitor_log}"
  fi
  find "${monitor_log}.1" -mtime +14 -delete 2>/dev/null || true
fi

# launchd keeps the old file descriptor after a rename. Restart the server so
# new output is written to the freshly created bounded log file.
if [[ "${server_log_rotated}" == true ]]; then
  launchctl kickstart -k "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  sleep 2
fi

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

http_code() {
  curl --silent --show-error --max-time "${CURL_TIMEOUT}" \
    --output /dev/null --write-out '%{http_code}' "$@" 2>/dev/null || true
}

issue_access_token() {
  local base_url="$1"
  local credential="$2"
  local gateway_key="$3"
  local response body response_code
  local gateway_header=()
  [[ -n "${gateway_key}" ]] && gateway_header=(--header "X-BodyMode-Gateway-Key: ${gateway_key}")
  response=$(curl --silent --show-error --max-time "${CURL_TIMEOUT}" \
    --header "Authorization: Bearer ${credential}" \
    --header "Content-Type: application/json" \
    "${gateway_header[@]}" \
    --data '{"installation_id":"bodymode-health-monitor-0001","app_version":"health-monitor"}' \
    --write-out $'\n%{http_code}' \
    "${base_url}/v1/auth/token" 2>/dev/null || true)
  response_code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  [[ "${response_code}" == "200" && -n "${PYTHON}" ]] || return 1
  print -r -- "${body}" | "${PYTHON}" -c \
    'import json,sys; value=json.load(sys.stdin).get("access_token", ""); print(value if isinstance(value, str) else "")' \
    2>/dev/null
}

authenticated_health_code() {
  local base_url="$1"
  local access_token="$2"
  local gateway_key="$3"
  local gateway_header=()
  [[ -n "${gateway_key}" ]] && gateway_header=(--header "X-BodyMode-Gateway-Key: ${gateway_key}")
  http_code --header "Authorization: Bearer ${access_token}" "${gateway_header[@]}" "${base_url}/v1/health"
}

authenticated_health_snapshot() {
  local base_url="$1"
  local access_token="$2"
  local gateway_key="$3"
  local gateway_header=()
  [[ -n "${gateway_key}" ]] && gateway_header=(--header "X-BodyMode-Gateway-Key: ${gateway_key}")
  curl --silent --show-error --max-time "${CURL_TIMEOUT}" \
    --header "Authorization: Bearer ${access_token}" "${gateway_header[@]}" \
    --write-out $'\n%{http_code}' "${base_url}/v1/health" 2>/dev/null || true
}

public_health_code_with_backoff() {
  local attempt=1
  local delay="${PUBLIC_HEALTH_INITIAL_BACKOFF_SECONDS}"
  local health_status=""

  while (( attempt <= PUBLIC_HEALTH_ATTEMPTS )); do
    health_status=$(authenticated_health_code "${PUBLIC_BASE_URL}" "${access_token}" "")
    [[ "${health_status}" == "200" ]] && { print -r -- "${health_status}"; return 0; }
    if (( attempt < PUBLIC_HEALTH_ATTEMPTS )); then
      sleep "${delay}"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done

  print -r -- "${health_status:-none}"
  return 1
}

restore_public_route() {
  [[ -x "${TAILSCALE_BIN}" && -S "${TAILSCALE_SOCKET}" ]] || return 1
  "${TAILSCALE_BIN}" --socket="${TAILSCALE_SOCKET}" funnel --bg --yes 8765 >/dev/null 2>&1
}

internal_status=$(http_code "${LOCAL_BASE_URL}/internal/health")
local_ready=false
public_ready=true
auth_status="none"
public_status="disabled"

credential=""
[[ -r "${CREDENTIAL_FILE}" ]] && credential="$(tr -d '\r\n' < "${CREDENTIAL_FILE}")"
gateway_key=""
[[ -r "${GATEWAY_KEY_FILE}" ]] && gateway_key="$(tr -d '\r\n' < "${GATEWAY_KEY_FILE}")"
access_token=""
inference_ready="unknown"
active_inference="unknown"
queued_inference="unknown"
if [[ "${internal_status}" == "200" && -n "${credential}" ]]; then
  access_token="$(issue_access_token "${LOCAL_BASE_URL}" "${credential}" "${gateway_key}" || true)"
fi
if [[ -n "${access_token}" ]]; then
  local_health_snapshot=$(authenticated_health_snapshot "${LOCAL_BASE_URL}" "${access_token}" "${gateway_key}")
  auth_status="${local_health_snapshot##*$'\n'}"
  local_health_body="${local_health_snapshot%$'\n'*}"
  if [[ "${auth_status}" == "200" && -n "${PYTHON}" ]]; then
    health_fields=$(print -r -- "${local_health_body}" | "${PYTHON}" -c '
import json, sys
try:
    value = json.load(sys.stdin)
    print("true" if value.get("inference_ready") is True else "false")
    print(int(value.get("active_inference", -1)))
    print(int(value.get("queued_inference", -1)))
except Exception:
    print("unknown")
    print("unknown")
    print("unknown")
' 2>/dev/null || true)
    inference_ready="${health_fields%%$'\n'*}"
    health_fields="${health_fields#*$'\n'}"
    active_inference="${health_fields%%$'\n'*}"
    queued_inference="${health_fields#*$'\n'}"
  fi
  [[ "${auth_status}" == "200" ]] && local_ready=true
fi

if [[ -n "${PUBLIC_BASE_URL}" ]]; then
  public_ready=false
  public_status="invalid_url"
  if [[ "${PUBLIC_BASE_URL}" == https://* && -n "${access_token}" ]]; then
    public_status=$(public_health_code_with_backoff || true)
    [[ "${public_status}" == "200" ]] && public_ready=true
  fi
fi

inference_degraded=false
if [[ "${local_ready}" == true && "${inference_ready}" == "false" \
  && "${active_inference}" == "0" && "${queued_inference}" == "0" ]]; then
  inference_degraded=true
fi

if [[ "${local_ready}" == true && "${public_ready}" == true && "${inference_degraded}" == false ]]; then
  print 0 > "${FAILURE_FILE}"
  print 0 > "${INFERENCE_FAILURE_FILE}"
  exit 0
fi

failures=0
[[ -r "${FAILURE_FILE}" ]] && failures=$(<"${FAILURE_FILE}")
failures=$((failures + 1))
print "${failures}" > "${FAILURE_FILE}"
print "${timestamp} readiness failed internal=${internal_status:-none} authenticated=${auth_status:-none} public=${public_status:-disabled} inference_ready=${inference_ready} active=${active_inference} queued=${queued_inference} consecutive=${failures}" >> "${LOG_DIR}/local-ai-monitor.log"

if [[ "${local_ready}" == true && "${public_ready}" != true ]] \
  && (( failures >= PUBLIC_RECOVERY_THRESHOLD )); then
  if restore_public_route; then
    sleep 2
    public_status=$(public_health_code_with_backoff || true)
    if [[ "${public_status}" == "200" ]]; then
      print "${timestamp} restored public route by reapplying Tailscale Funnel" >> "${LOG_DIR}/local-ai-monitor.log"
      print 0 > "${FAILURE_FILE}"
      print 0 > "${INFERENCE_FAILURE_FILE}"
      exit 0
    fi
  fi
  print "${timestamp} public endpoint remained unavailable after Tailscale Funnel recovery" >> "${LOG_DIR}/local-ai-monitor.log"
  print 0 > "${FAILURE_FILE}"
fi

if [[ "${inference_degraded}" == true ]]; then
  inference_failures=0
  [[ -r "${INFERENCE_FAILURE_FILE}" ]] && inference_failures=$(<"${INFERENCE_FAILURE_FILE}")
  inference_failures=$((inference_failures + 1))
  print "${inference_failures}" > "${INFERENCE_FAILURE_FILE}"
  if (( inference_failures >= INFERENCE_RECOVERY_THRESHOLD )); then
    launchctl kickstart -k "${DOMAIN}/${LABEL}" >> "${LOG_DIR}/local-ai-monitor.log" 2>&1 || true
    print "${timestamp} restarted ${LABEL} after ${inference_failures} idle degraded inference checks" >> "${LOG_DIR}/local-ai-monitor.log"
    print 0 > "${INFERENCE_FAILURE_FILE}"
  fi
else
  print 0 > "${INFERENCE_FAILURE_FILE}"
fi

if [[ "${local_ready}" != true ]] && (( failures >= 3 )); then
  launchctl kickstart -k "${DOMAIN}/${LABEL}" >> "${LOG_DIR}/local-ai-monitor.log" 2>&1 || true
  print "${timestamp} restarted ${LABEL}" >> "${LOG_DIR}/local-ai-monitor.log"
  print 0 > "${FAILURE_FILE}"
fi

exit 1
