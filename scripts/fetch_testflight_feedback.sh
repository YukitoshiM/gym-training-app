#!/usr/bin/env bash

set -euo pipefail

APP_ID="${BODYMODE_APP_ID:-6799871527}"
CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"
OUTPUT_DIR="${1:-.build/TestFlightFeedback}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER_PATH="${BODYMODE_FEEDBACK_LEDGER_PATH:-${SCRIPT_DIR}/../docs/testflight_feedback_ledger.md}"

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

mkdir -p "${OUTPUT_DIR}/screenshots"
chmod 700 "${OUTPUT_DIR}"

base64_url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now="$(date +%s)"
expires_at="$((now + 1200))"
header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "${KEY_ID}" | base64_url)"
payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "${ISSUER_ID}" "${now}" "${expires_at}" | base64_url)"
signing_input="${header}.${payload}"
signature_path="$(mktemp /tmp/bodymode-asc-signature.XXXXXX)"
trap 'rm -f "${signature_path}"' EXIT

printf '%s' "${signing_input}" | openssl dgst -sha256 -sign "${KEY_PATH}" -out "${signature_path}"
signature="$({ python3 - "${signature_path}" <<'PY'
import base64
import sys

encoded = open(sys.argv[1], "rb").read()
position = 1
length = encoded[position]
position += 1
if length & 0x80:
    byte_count = length & 0x7F
    position += byte_count

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

feedback_url="https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/betaFeedbackScreenshotSubmissions?include=build,tester&limit=200&sort=-createdDate&fields%5BbetaFeedbackScreenshotSubmissions%5D=createdDate,comment,email,deviceModel,osVersion,locale,timeZone,architecture,connectionType,pairedAppleWatch,appUptimeInMilliseconds,diskBytesAvailable,diskBytesTotal,batteryPercentage,screenWidthInPoints,screenHeightInPoints,appPlatform,devicePlatform,deviceFamily,buildBundleId,screenshots,build,tester&fields%5BbetaTesters%5D=firstName,lastName,email,inviteType,state&fields%5Bbuilds%5D=version,uploadedDate"
crash_url="https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/betaFeedbackCrashSubmissions?include=build,tester&limit=200&sort=-createdDate"
builds_url="https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=${APP_ID}&limit=50&sort=-uploadedDate"

curl --fail --silent --show-error \
  -H "Authorization: Bearer ${token}" \
  "${feedback_url}" \
  -o "${OUTPUT_DIR}/feedback.json"

curl --fail --silent --show-error \
  -H "Authorization: Bearer ${token}" \
  "${crash_url}" \
  -o "${OUTPUT_DIR}/crashes.json"

curl --fail --silent --show-error \
  -H "Authorization: Bearer ${token}" \
  "${builds_url}" \
  -o "${OUTPUT_DIR}/builds.json"

jq -r '.data[] | [.id, .attributes.screenshots[0].url] | @tsv' "${OUTPUT_DIR}/feedback.json" |
  while IFS=$'\t' read -r feedback_id screenshot_url; do
    [[ -n "${screenshot_url}" ]] || continue
    curl --fail --silent --show-error \
      "${screenshot_url}" \
      -o "${OUTPUT_DIR}/screenshots/${feedback_id}.jpg"
  done

jq -r '
  (.included // []) as $included |
  .data[] |
  . as $feedback |
  ($included[]? | select(.type == "builds" and .id == $feedback.relationships.build.data.id)) as $build |
  "## \($feedback.attributes.createdDate) / Build \($build.attributes.version // "不明")\n\n" +
  "- ID: `\($feedback.id)`\n" +
  "- 端末: \($feedback.attributes.deviceModel // "不明") / iOS \($feedback.attributes.osVersion // "不明")\n" +
  "- コメント: \($feedback.attributes.comment // "コメントなし")\n" +
  "- 画像: `screenshots/\($feedback.id).jpg`\n"
' "${OUTPUT_DIR}/feedback.json" > "${OUTPUT_DIR}/feedback.md"

: > "${OUTPUT_DIR}/untriaged.md"
while IFS= read -r feedback_id; do
  if [[ -r "${LEDGER_PATH}" ]] && grep -Fq "\`${feedback_id}\`" "${LEDGER_PATH}"; then
    continue
  fi

  jq -r --arg feedback_id "${feedback_id}" '
    (.included // []) as $included |
    .data[] |
    select(.id == $feedback_id) |
    . as $feedback |
    ($included[]? | select(.type == "builds" and .id == $feedback.relationships.build.data.id)) as $build |
    "## \($feedback.attributes.createdDate) / Build \($build.attributes.version // "不明")\n\n" +
    "- ID: `\($feedback.id)`\n" +
    "- 端末: \($feedback.attributes.deviceModel // "不明") / iOS \($feedback.attributes.osVersion // "不明")\n" +
    "- コメント: \($feedback.attributes.comment // "コメントなし")\n" +
    "- 画像: `screenshots/\($feedback.id).jpg`\n"
  ' "${OUTPUT_DIR}/feedback.json" >> "${OUTPUT_DIR}/untriaged.md"
done < <(jq -r '.data[].id' "${OUTPUT_DIR}/feedback.json")

feedback_count="$(jq '.data | length' "${OUTPUT_DIR}/feedback.json")"
crash_count="$(jq '.data | length' "${OUTPUT_DIR}/crashes.json")"
untriaged_count="$(grep -c '^## ' "${OUTPUT_DIR}/untriaged.md" || true)"
latest_build="$(jq -r '.data[0].attributes.version // "なし"' "${OUTPUT_DIR}/builds.json")"
latest_build_state="$(jq -r '.data[0].attributes.processingState // "不明"' "${OUTPUT_DIR}/builds.json")"
echo "TestFlight feedback: ${feedback_count}"
echo "Untriaged feedback: ${untriaged_count}"
echo "TestFlight crashes: ${crash_count}"
echo "Latest build: ${latest_build} (${latest_build_state})"
echo "Saved to: ${OUTPUT_DIR}"
