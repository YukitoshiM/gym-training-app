#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SERVER_DIR="${REPO_ROOT}/local_llm_server"
GATEWAY_URL_FILE="${SERVER_DIR}/.gateway_url"
ORIGIN_FILE="${SERVER_DIR}/.gateway_origin_url"
SECRET_SOURCE="${HOME}/Library/Application Support/BodyMode/Gateway/gateway_shared_secret"
SECRET_TARGET="${SERVER_DIR}/.gateway_shared_secret"

if [[ "${1:-}" != "--confirm-all-active-builds-use-gateway" || $# -ne 1 ]]; then
  print "This blocks direct AI access used by older TestFlight builds." >&2
  print "After all active testers have upgraded, run:" >&2
  print "  $0 --confirm-all-active-builds-use-gateway" >&2
  exit 64
fi

for file in "${GATEWAY_URL_FILE}" "${ORIGIN_FILE}" "${SECRET_SOURCE}"; do
  if [[ ! -s "${file}" ]]; then
    print "Required gateway state is missing: ${file}" >&2
    exit 66
  fi
done

gateway_url="$(tr -d '\r\n' < "${GATEWAY_URL_FILE}")"
origin_url="$(tr -d '\r\n' < "${ORIGIN_FILE}")"
if [[ "${gateway_url}" != https://* || "${origin_url}" != https://* ]]; then
  print "Gateway and origin URLs must both use HTTPS" >&2
  exit 65
fi

install -m 600 "${SECRET_SOURCE}" "${SECRET_TARGET}"
"${SCRIPT_DIR}/install_local_ai_launch_agent.sh"

direct_status=""
for attempt in {1..8}; do
  direct_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    "${origin_url}/v1/health" 2>/dev/null || true)"
  [[ "${direct_status}" == "403" ]] && break
  sleep 2
done
if [[ "${direct_status}" != "403" ]]; then
  print "Direct-origin blocking did not activate; expected HTTP 403, received ${direct_status}" >&2
  exit 70
fi

credential_file="${HOME}/Library/Application Support/BodyMode/local_ai_server/.health_enrollment_key"
if [[ ! -s "${credential_file}" ]]; then
  credential_file="${SERVER_DIR}/.health_enrollment_key"
fi
if [[ ! -s "${credential_file}" ]]; then
  credential_file="${SERVER_DIR}/.api_key"
fi
credential="$(tr -d '\r\n' < "${credential_file}")"
token_response="$(curl --silent --show-error --fail-with-body --max-time 30 \
  --header "Authorization: Bearer ${credential}" \
  --header "Content-Type: application/json" \
  --data '{"installation_id":"bodymode-gateway-activation-0001","app_version":"gateway-activation"}' \
  "${gateway_url}/v1/auth/token")"
access_token="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token", ""))' <<<"${token_response}")"
health_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
  --header "Authorization: Bearer ${access_token}" \
  "${gateway_url}/v1/health")"
if [[ -z "${access_token}" || "${health_status}" != "200" ]]; then
  print "Gateway verification failed after direct-origin blocking" >&2
  exit 70
fi

print "Gateway-only mode is active. Direct origin: HTTP 403. Gateway: HTTP 200."
