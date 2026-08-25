#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
GATEWAY_DIR="${REPO_ROOT}/cloudflare_ai_gateway"
SERVER_DIR="${REPO_ROOT}/local_llm_server"
LOCAL_CONFIG="${REPO_ROOT}/Config/AIService.local.xcconfig"
ORIGIN_FILE="${SERVER_DIR}/.gateway_origin_url"
GATEWAY_URL_FILE="${SERVER_DIR}/.gateway_url"
CURRENT_PUBLIC_URL_FILE="${SERVER_DIR}/.public_base_url"
SECRET_DIR="${HOME}/Library/Application Support/BodyMode/Gateway"
PENDING_SECRET_FILE="${SECRET_DIR}/gateway_shared_secret"
DEPLOY_OUTPUT="${GATEWAY_DIR}/.deploy-output.txt"

print_usage() {
  print "Usage: $0 [--origin https://origin.example] [--gateway-url https://worker.workers.dev] [--skip-app-config]"
}

origin_url="${BODYMODE_AI_ORIGIN_URL:-}"
gateway_url="${BODYMODE_AI_GATEWAY_URL:-}"
update_app_config=true

while (( $# > 0 )); do
  case "$1" in
    --origin)
      [[ $# -ge 2 ]] || { print_usage >&2; exit 64; }
      origin_url="$2"
      shift 2
      ;;
    --gateway-url)
      [[ $# -ge 2 ]] || { print_usage >&2; exit 64; }
      gateway_url="$2"
      shift 2
      ;;
    --skip-app-config)
      update_app_config=false
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print "Unknown argument: $1" >&2
      print_usage >&2
      exit 64
      ;;
  esac
done

if [[ ! -d "${GATEWAY_DIR}/node_modules/wrangler" ]]; then
  print "Installing the pinned Cloudflare CLI dependency"
  npm install --prefix "${GATEWAY_DIR}"
fi

if ! (cd "${GATEWAY_DIR}" && npx wrangler whoami 2>/dev/null | grep -q "You are logged in"); then
  print "Cloudflare CLI is not authenticated. Run this once, then rerun this script:" >&2
  print "  cd ${GATEWAY_DIR:q} && npx wrangler login" >&2
  exit 69
fi

if [[ -z "${origin_url}" && -s "${ORIGIN_FILE}" ]]; then
  origin_url="$(tr -d '\r\n' < "${ORIGIN_FILE}")"
fi
if [[ -z "${origin_url}" && -s "${CURRENT_PUBLIC_URL_FILE}" ]]; then
  origin_url="$(tr -d '\r\n' < "${CURRENT_PUBLIC_URL_FILE}")"
fi
if [[ "${origin_url}" != https://* ]]; then
  print "An HTTPS origin is required. Pass --origin or configure ${CURRENT_PUBLIC_URL_FILE}" >&2
  exit 65
fi
if [[ "${origin_url}" == *workers.dev* ]]; then
  print "The origin must be the direct Mac mini tunnel URL, not the Worker URL" >&2
  exit 65
fi

mkdir -p "${SECRET_DIR}"
chmod 700 "${SECRET_DIR}"
if [[ ! -s "${PENDING_SECRET_FILE}" ]]; then
  umask 077
  openssl rand -hex 32 > "${PENDING_SECRET_FILE}"
fi
chmod 600 "${PENDING_SECRET_FILE}"

print -r -- "${origin_url}" > "${ORIGIN_FILE}"
chmod 600 "${ORIGIN_FILE}"

print "Uploading encrypted Worker secrets"
print -rn -- "${origin_url}" | (cd "${GATEWAY_DIR}" && npx wrangler secret put BODYMODE_ORIGIN_URL >/dev/null)
tr -d '\r\n' < "${PENDING_SECRET_FILE}" | (cd "${GATEWAY_DIR}" && npx wrangler secret put BODYMODE_GATEWAY_KEY >/dev/null)

print "Deploying BodyMode AI gateway"
(cd "${GATEWAY_DIR}" && npx wrangler deploy) 2>&1 | tee "${DEPLOY_OUTPUT}"

if [[ -z "${gateway_url}" ]]; then
  gateway_url="$(grep -Eo 'https://[A-Za-z0-9.-]+\.workers\.dev' "${DEPLOY_OUTPUT}" | tail -n 1 || true)"
fi
if [[ "${gateway_url}" != https://* ]]; then
  print "Deployment finished, but the Worker URL could not be detected." >&2
  print "Rerun with --gateway-url https://<worker>.<account>.workers.dev" >&2
  exit 65
fi

gateway_url="${gateway_url%/}"
if [[ "${gateway_url}" == https://*/* ]]; then
  print "The Worker base URL must not contain a path: ${gateway_url}" >&2
  exit 65
fi
print -r -- "${gateway_url}" > "${GATEWAY_URL_FILE}"
print -r -- "${gateway_url}" > "${CURRENT_PUBLIC_URL_FILE}"
chmod 600 "${GATEWAY_URL_FILE}" "${CURRENT_PUBLIC_URL_FILE}"

credential_file="${HOME}/Library/Application Support/BodyMode/local_ai_server/.health_enrollment_key"
if [[ ! -s "${credential_file}" ]]; then
  credential_file="${SERVER_DIR}/.health_enrollment_key"
fi
if [[ ! -s "${credential_file}" ]]; then
  credential_file="${SERVER_DIR}/.api_key"
fi
if [[ ! -s "${credential_file}" ]]; then
  print "Gateway deployed, but no local health credential is available for verification" >&2
  exit 66
fi

credential="$(tr -d '\r\n' < "${credential_file}")"
token_response="$(curl --silent --show-error --fail-with-body --max-time 30 \
  --header "Authorization: Bearer ${credential}" \
  --header "Content-Type: application/json" \
  --data '{"installation_id":"bodymode-gateway-deploy-0001","app_version":"gateway-deploy"}' \
  "${gateway_url}/v1/auth/token")"
access_token="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token", ""))' <<<"${token_response}")"
if [[ -z "${access_token}" ]]; then
  print "Gateway token verification failed" >&2
  exit 70
fi

health_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
  --header "Authorization: Bearer ${access_token}" \
  "${gateway_url}/v1/health")"
if [[ "${health_status}" != "200" ]]; then
  print "Gateway health verification failed with HTTP ${health_status}" >&2
  exit 70
fi

ssv_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
  "${gateway_url}/v1/credits/rewarded-ad/ssv")"
if [[ "${ssv_status}" != "400" ]]; then
  print "Gateway rewarded-ad SSV route verification failed with HTTP ${ssv_status}" >&2
  exit 70
fi

if [[ "${update_app_config}" == true ]]; then
  [[ -f "${LOCAL_CONFIG}" ]] || touch "${LOCAL_CONFIG}"
  current_version="$(awk -F= '/^[[:space:]]*BODYMODE_AI_CONFIGURATION_VERSION[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "${LOCAL_CONFIG}")"
  if [[ ! "${current_version}" =~ '^[0-9]+$' ]]; then
    current_version=0
  fi
  next_version=$((current_version + 1))
  xcconfig_base_url="https:/\$()/${gateway_url#https://}"
  temp_config="$(mktemp "${TMPDIR:-/tmp}/bodymode-ai-config.XXXXXX")"
  awk -v base_url="${xcconfig_base_url}" -v version="${next_version}" '
    BEGIN { saw_url = 0; saw_version = 0 }
    /^[[:space:]]*BODYMODE_AI_BASE_URL[[:space:]]*=/ {
      print "BODYMODE_AI_BASE_URL = " base_url
      saw_url = 1
      next
    }
    /^[[:space:]]*BODYMODE_AI_CONFIGURATION_VERSION[[:space:]]*=/ {
      print "BODYMODE_AI_CONFIGURATION_VERSION = " version
      saw_version = 1
      next
    }
    { print }
    END {
      if (!saw_url) print "BODYMODE_AI_BASE_URL = " base_url
      if (!saw_version) print "BODYMODE_AI_CONFIGURATION_VERSION = " version
    }
  ' "${LOCAL_CONFIG}" > "${temp_config}"
  chmod 600 "${temp_config}"
  mv "${temp_config}" "${LOCAL_CONFIG}"
  print "Updated the local Release AI URL and configuration version"
fi

print "Gateway is healthy: ${gateway_url}"
print "Rewarded-ad SSV route is reachable and rejects unsigned callbacks."
print "Direct-origin blocking remains OFF for existing TestFlight builds."
print "After every active build uses the gateway, run scripts/activate_ai_gateway_only_mode.sh with its confirmation flag."
