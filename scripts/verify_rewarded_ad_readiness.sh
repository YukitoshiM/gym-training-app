#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/.build/TestFlightPreflight/Build/Products/Release-iphoneos/GymTrainingApp.app}"
SERVER_ENV="${BODYMODE_SERVER_ENV_PATH:-${ROOT_DIR}/local_llm_server/.env.local}"

if [[ ! -f "${APP_PATH}/Info.plist" ]]; then
  echo "error: built app Info.plist not found; run testflight_preflight.sh first" >&2
  exit 1
fi
if [[ ! -r "${SERVER_ENV}" ]]; then
  echo "error: server environment is not readable" >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

app_rewarded_id="$(plist_value "${APP_PATH}/Info.plist" BodyModeAdRewardedUnitID)"
server_rewarded_id="$(sed -n 's/^ADMOB_REWARDED_AD_UNIT_ID=//p' "${SERVER_ENV}" | tail -1 | tr -d '"[:space:]')"
gateway_url="$(plist_value "${APP_PATH}/Info.plist" BodyModeAIBaseURL)"

ad_unit_pattern='^ca-app-pub-[0-9]{16}/[0-9]{10}$'
if [[ ! "${app_rewarded_id}" =~ ${ad_unit_pattern} ]]; then
  echo "error: the app does not contain a production rewarded AdMob identifier" >&2
  exit 1
fi
if [[ ! "${server_rewarded_id}" =~ ${ad_unit_pattern} ]]; then
  echo "error: the server does not contain a production rewarded AdMob identifier" >&2
  exit 1
fi
if [[ "${app_rewarded_id}" != "${server_rewarded_id}" ]]; then
  echo "error: app and server rewarded AdMob identifiers do not match" >&2
  exit 1
fi
if [[ ! "${gateway_url}" =~ ^https://[^/]+$ ]]; then
  echo "error: the built app does not contain a valid HTTPS gateway URL" >&2
  exit 1
fi

response_path="$(mktemp "${TMPDIR:-/tmp}/bodymode-rewarded-readiness.XXXXXX")"
trap 'rm -f "${response_path}"' EXIT
status="$(curl --silent --show-error --max-time 30 \
  --output "${response_path}" --write-out '%{http_code}' \
  "${gateway_url}/v1/credits/rewarded-ad/ssv")"

if [[ "${status}" != "400" ]]; then
  echo "error: public rewarded-ad SSV route returned HTTP ${status}, expected 400 for an unsigned callback" >&2
  exit 1
fi

echo "Rewarded-ad production readiness: PASS"
echo "App/server ad unit match: PASS"
echo "Public SSV route: PASS"
