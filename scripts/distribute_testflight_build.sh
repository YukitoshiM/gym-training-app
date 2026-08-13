#!/usr/bin/env bash

set -euo pipefail

APP_ID="${BODYMODE_APP_ID:-6799871527}"
GROUP_ID="${BODYMODE_EXTERNAL_BETA_GROUP_ID:-b225e57c-460f-428e-98bb-c23eebb14c86}"
CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"
BUILD_NUMBER="${1:-}"

if [[ -z "${BUILD_NUMBER}" ]]; then
  echo "usage: $0 <build-number>" >&2
  exit 64
fi

if [[ ! -r "${CONFIG_PATH}" ]]; then
  echo "error: App Store Connect API config not found: ${CONFIG_PATH}" >&2
  exit 1
fi

KEY_ID="$(plutil -extract KeyID raw -expect string "${CONFIG_PATH}")"
ISSUER_ID="$(plutil -extract IssuerID raw -expect string "${CONFIG_PATH}")"
KEY_PATH="$(plutil -extract KeyPath raw -expect string "${CONFIG_PATH}")"

if [[ ! -r "${KEY_PATH}" ]]; then
  echo "error: App Store Connect API key is not readable: ${KEY_PATH}" >&2
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

api_get() {
  curl --fail --silent --show-error \
    -H "Authorization: Bearer ${token}" \
    "$1"
}

builds_json="$(api_get "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=${APP_ID}&limit=200&sort=-uploadedDate")"
build_id="$(jq -r --arg build "${BUILD_NUMBER}" '.data[] | select(.attributes.version == $build and .attributes.expired == false) | .id' <<<"${builds_json}" | head -1)"

if [[ -z "${build_id}" ]]; then
  echo "Build ${BUILD_NUMBER}: not visible in App Store Connect yet. Retry after processing starts."
  exit 2
fi

processing_state="$(jq -r --arg id "${build_id}" '.data[] | select(.id == $id) | .attributes.processingState' <<<"${builds_json}")"
echo "Build ${BUILD_NUMBER}: ${processing_state}"

if [[ "${processing_state}" != "VALID" ]]; then
  echo "Build ${BUILD_NUMBER}: processing has not completed."
  exit 2
fi

group_json="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}")"
group_name="$(jq -r '.data.attributes.name // "External Testers"' <<<"${group_json}")"
public_link="$(jq -r '.data.attributes.publicLink // empty' <<<"${group_json}")"
group_builds_json="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}/builds?limit=200")"

if jq -e --arg id "${build_id}" '.data[] | select(.id == $id)' <<<"${group_builds_json}" >/dev/null; then
  echo "External group: already assigned to ${group_name}"
else
  relationship_body="$(jq -nc --arg id "${build_id}" '{data: [{type: "builds", id: $id}]}')"
  http_status="$(curl --silent --show-error \
    -o "${response_path}" \
    -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -H 'Content-Type: application/json' \
    -d "${relationship_body}" \
    "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}/relationships/builds")"

  if [[ "${http_status}" != "204" ]]; then
    echo "error: could not assign build to external group (HTTP ${http_status})" >&2
    jq -r '.errors[]? | [.code, .title, .detail] | @tsv' "${response_path}" >&2
    exit 1
  fi
  echo "External group: assigned to ${group_name}"
fi

detail_json="$(api_get "https://api.appstoreconnect.apple.com/v1/builds/${build_id}/buildBetaDetail")"
external_state="$(jq -r '.data.attributes.externalBuildState // "UNKNOWN"' <<<"${detail_json}")"
echo "External state: ${external_state}"

if [[ "${external_state}" == "READY_FOR_BETA_SUBMISSION" ]]; then
  submission_body="$(jq -nc --arg id "${build_id}" '{data: {type: "betaAppReviewSubmissions", relationships: {build: {data: {type: "builds", id: $id}}}}}')"
  http_status="$(curl --silent --show-error \
    -o "${response_path}" \
    -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -H 'Content-Type: application/json' \
    -d "${submission_body}" \
    'https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions')"

  if [[ "${http_status}" != "201" ]]; then
    echo "error: could not submit build for Beta App Review (HTTP ${http_status})" >&2
    jq -r '.errors[]? | [.code, .title, .detail] | @tsv' "${response_path}" >&2
    exit 1
  fi
  echo "Beta App Review: submitted"
  detail_json="$(api_get "https://api.appstoreconnect.apple.com/v1/builds/${build_id}/buildBetaDetail")"
  external_state="$(jq -r '.data.attributes.externalBuildState // "UNKNOWN"' <<<"${detail_json}")"
  echo "External state: ${external_state}"
fi

if [[ -n "${public_link}" ]]; then
  echo "Public link: ${public_link}"
fi

if [[ "${external_state}" == "IN_BETA_TESTING" ]]; then
  echo "Build ${BUILD_NUMBER} is available to external testers."
else
  echo "Build ${BUILD_NUMBER} is assigned and awaiting Apple's external testing state transition."
fi
