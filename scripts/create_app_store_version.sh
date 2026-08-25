#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${BODYMODE_APP_ID:-6799871527}"
VERSION="${1:-$(awk '/MARKETING_VERSION:/ {print $2; exit}' "${ROOT_DIR}/project.yml")}"
CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"
METADATA_PATH="${ROOT_DIR}/Config/app_store_metadata.json"

if [[ ! -r "${CONFIG_PATH}" ]]; then
  echo "error: App Store Connect API config not found: ${CONFIG_PATH}" >&2
  exit 1
fi

if [[ ! -r "${METADATA_PATH}" ]]; then
  echo "error: App Store metadata not found: ${METADATA_PATH}" >&2
  exit 1
fi

USES_IDFA="$(jq -r '.usesIdfa' "${METADATA_PATH}")"
if [[ "${USES_IDFA}" != "true" && "${USES_IDFA}" != "false" ]]; then
  echo "error: Config/app_store_metadata.json must define usesIdfa as a boolean" >&2
  exit 1
fi

KEY_ID="$(plutil -extract KeyID raw -expect string "${CONFIG_PATH}")"
ISSUER_ID="$(plutil -extract IssuerID raw -expect string "${CONFIG_PATH}")"
KEY_PATH="$(plutil -extract KeyPath raw -expect string "${CONFIG_PATH}")"

if [[ ! -r "${KEY_PATH}" ]]; then
  echo "error: configured App Store Connect API key is not readable" >&2
  exit 1
fi

base64_url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now="$(date +%s)"
expires_at="$((now + 1200))"
header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "${KEY_ID}" | base64_url)"
payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "${ISSUER_ID}" "${now}" "${expires_at}" | base64_url)"
signing_input="${header}.${payload}"
signature_path="$(mktemp /tmp/bodymode-asc-signature.XXXXXX)"
response_path="$(mktemp /tmp/bodymode-asc-response.XXXXXX)"
trap 'rm -f "${signature_path}" "${response_path}"' EXIT

printf '%s' "${signing_input}" | openssl dgst -sha256 -sign "${KEY_PATH}" -out "${signature_path}"
signature="$({ python3 - "${signature_path}" <<'PY'
import base64
import sys

encoded = open(sys.argv[1], "rb").read()
position = 1
length = encoded[position]
position += 1
if length & 0x80:
    position += length & 0x7F
if encoded[position] != 2:
    raise ValueError("invalid DER signature")
position += 1
r_length = encoded[position]
position += 1
r = encoded[position:position + r_length]
position += r_length
if encoded[position] != 2:
    raise ValueError("invalid DER signature")
position += 1
s_length = encoded[position]
position += 1
s = encoded[position:position + s_length]
r = r.lstrip(b"\0").rjust(32, b"\0")
s = s.lstrip(b"\0").rjust(32, b"\0")
print(base64.urlsafe_b64encode(r + s).rstrip(b"=").decode())
PY
} )"
token="${signing_input}.${signature}"

versions_json="$(curl --fail --silent --show-error \
  -H "Authorization: Bearer ${token}" \
  "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appStoreVersions?limit=50")"
existing_id="$(jq -r --arg version "${VERSION}" '.data[] | select(.attributes.platform == "IOS" and .attributes.versionString == $version) | .id' <<<"${versions_json}" | head -1)"

if [[ -n "${existing_id}" ]]; then
  echo "App Store version ${VERSION} already exists: ${existing_id}"
  exit 0
fi

body="$(jq -nc \
  --arg app_id "${APP_ID}" \
  --arg version "${VERSION}" \
  --argjson uses_idfa "${USES_IDFA}" \
  '{data: {type: "appStoreVersions", attributes: {platform: "IOS", versionString: $version, releaseType: "MANUAL", usesIdfa: $uses_idfa}, relationships: {app: {data: {type: "apps", id: $app_id}}}}}')"
status="$(curl --silent --show-error -o "${response_path}" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer ${token}" \
  -H 'Content-Type: application/json' \
  -d "${body}" \
  'https://api.appstoreconnect.apple.com/v1/appStoreVersions')"

if [[ "${status}" != "201" ]]; then
  echo "error: could not create App Store version ${VERSION} (HTTP ${status})" >&2
  jq -r '.errors[]? | [.code, .title, .detail] | @tsv' "${response_path}" >&2
  exit 1
fi

version_id="$(jq -r '.data.id' "${response_path}")"
state="$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // "UNKNOWN"' "${response_path}")"
echo "Created App Store version ${VERSION}: ${version_id}"
echo "State: ${state}"
echo "Release type: MANUAL"
echo "Uses IDFA: ${USES_IDFA}"
