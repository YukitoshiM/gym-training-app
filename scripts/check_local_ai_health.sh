#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
LABEL="com.yukitoshim.gymtraining.local-llm"
DOMAIN="gui/${UID}"
STATE_DIR="${HOME}/Library/Application Support/BodyMode/monitor"
FAILURE_FILE="${STATE_DIR}/local-ai-consecutive-failures"
LOG_DIR="${HOME}/Library/Logs/BodyMode"
MAX_LOG_BYTES=$((5 * 1024 * 1024))
LOCAL_BASE_URL="${BODYMODE_AI_LOCAL_BASE_URL:-http://127.0.0.1:8765}"
PUBLIC_URL_FILE="${BODYMODE_AI_PUBLIC_BASE_URL_FILE:-${SCRIPT_DIR}/.public_base_url}"
CREDENTIAL_FILE="${BODYMODE_AI_HEALTH_CREDENTIAL_FILE:-${SCRIPT_DIR}/.health_enrollment_key}"
CURL_TIMEOUT="${BODYMODE_AI_HEALTH_TIMEOUT_SECONDS:-12}"

if [[ ! -r "${CREDENTIAL_FILE}" ]]; then
  CREDENTIAL_FILE="${SCRIPT_DIR}/.api_key"
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

for log in "${LOG_DIR}/local-ai.log" "${LOG_DIR}/local-ai.error.log" "${LOG_DIR}/local-ai-monitor.log"; do
  [[ -f "${log}" ]] || continue
  size=$(stat -f %z "${log}")
  if (( size > MAX_LOG_BYTES )); then
    mv -f "${log}" "${log}.1"
    : > "${log}"
  fi
done

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

http_code() {
  curl --silent --show-error --max-time "${CURL_TIMEOUT}" \
    --output /dev/null --write-out '%{http_code}' "$@" 2>/dev/null || true
}

issue_access_token() {
  local base_url="$1"
  local credential="$2"
  local response body response_code
  response=$(curl --silent --show-error --max-time "${CURL_TIMEOUT}" \
    --header "Authorization: Bearer ${credential}" \
    --header "Content-Type: application/json" \
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
  http_code --header "Authorization: Bearer ${access_token}" "${base_url}/v1/health"
}

internal_status=$(http_code "${LOCAL_BASE_URL}/internal/health")
local_ready=false
public_ready=true
auth_status="none"
public_status="disabled"

credential=""
[[ -r "${CREDENTIAL_FILE}" ]] && credential="$(tr -d '\r\n' < "${CREDENTIAL_FILE}")"
access_token=""
if [[ "${internal_status}" == "200" && -n "${credential}" ]]; then
  access_token="$(issue_access_token "${LOCAL_BASE_URL}" "${credential}" || true)"
fi
if [[ -n "${access_token}" ]]; then
  auth_status=$(authenticated_health_code "${LOCAL_BASE_URL}" "${access_token}")
  [[ "${auth_status}" == "200" ]] && local_ready=true
fi

if [[ -n "${PUBLIC_BASE_URL}" ]]; then
  public_ready=false
  public_status="invalid_url"
  if [[ "${PUBLIC_BASE_URL}" == https://* && -n "${access_token}" ]]; then
    public_status=$(authenticated_health_code "${PUBLIC_BASE_URL}" "${access_token}")
    [[ "${public_status}" == "200" ]] && public_ready=true
  fi
fi

if [[ "${local_ready}" == true && "${public_ready}" == true ]]; then
  print 0 > "${FAILURE_FILE}"
  exit 0
fi

failures=0
[[ -r "${FAILURE_FILE}" ]] && failures=$(<"${FAILURE_FILE}")
failures=$((failures + 1))
print "${failures}" > "${FAILURE_FILE}"
print "${timestamp} readiness failed internal=${internal_status:-none} authenticated=${auth_status:-none} public=${public_status:-disabled} consecutive=${failures}" >> "${LOG_DIR}/local-ai-monitor.log"

if (( failures >= 3 )); then
  if [[ "${local_ready}" != true ]]; then
    launchctl kickstart -k "${DOMAIN}/${LABEL}" >> "${LOG_DIR}/local-ai-monitor.log" 2>&1 || true
    print "${timestamp} restarted ${LABEL}" >> "${LOG_DIR}/local-ai-monitor.log"
  else
    print "${timestamp} public endpoint failed; local server was not restarted" >> "${LOG_DIR}/local-ai-monitor.log"
  fi
  print 0 > "${FAILURE_FILE}"
fi

exit 1
