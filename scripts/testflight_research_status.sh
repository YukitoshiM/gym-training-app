#!/usr/bin/env bash

set -euo pipefail

APP_ID="${BODYMODE_APP_ID:-6799871527}"
GROUP_ID="${BODYMODE_RESEARCH_BETA_GROUP_ID:-03450576-575a-4a96-8079-777d2ded3be0}"
CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"
MODE="${1:-}"

if [[ -n "${MODE}" && "${MODE}" != "--all-groups" ]]; then
  echo "usage: $0 [--all-groups]" >&2
  exit 2
fi

if [[ ! -r "${CONFIG_PATH}" ]]; then
  echo "error: App Store Connect API config not found" >&2
  exit 1
fi

KEY_ID="$(plutil -extract KeyID raw -expect string "${CONFIG_PATH}")"
ISSUER_ID="$(plutil -extract IssuerID raw -expect string "${CONFIG_PATH}")"
KEY_PATH="$(plutil -extract KeyPath raw -expect string "${CONFIG_PATH}")"

if [[ ! -r "${KEY_PATH}" ]]; then
  echo "error: App Store Connect API key is not readable" >&2
  exit 1
fi

base64_url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now="$(date +%s)"
header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "${KEY_ID}" | base64_url)"
payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
  "${ISSUER_ID}" "${now}" "$((now + 1200))" | base64_url)"
signing_input="${header}.${payload}"
signature_path="$(mktemp /tmp/bodymode-research-status.XXXXXX)"
trap 'rm -f "${signature_path}"' EXIT
printf '%s' "${signing_input}" | openssl dgst -sha256 -sign "${KEY_PATH}" -out "${signature_path}"
signature="$(python3 - "${signature_path}" <<'PY'
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
)"
token="${signing_input}.${signature}"

api_get() {
  curl --fail --silent --show-error -H "Authorization: Bearer ${token}" "$1"
}

if [[ "${MODE}" == "--all-groups" ]]; then
  groups_json="$(api_get "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/betaGroups?limit=200&fields%5BbetaGroups%5D=name,isInternalGroup,publicLinkEnabled,publicLinkLimitEnabled,publicLinkLimit,feedbackEnabled")"
  report='[]'
  while IFS= read -r group_id; do
    [[ -n "${group_id}" ]] || continue
    group="$(jq --arg id "${group_id}" '.data[] | select(.id == $id)' <<<"${groups_json}")"
    testers="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${group_id}/betaTesters?limit=200&fields%5BbetaTesters%5D=state,inviteType")"
    builds="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${group_id}/builds?limit=200&fields%5Bbuilds%5D=version,processingState,expired")"
    report="$(jq -n \
      --argjson report "${report}" \
      --argjson group "${group}" \
      --argjson testers "${testers}" \
      --argjson builds "${builds}" \
      '$report + [{
        name: $group.attributes.name,
        is_internal: $group.attributes.isInternalGroup,
        public_link_enabled: $group.attributes.publicLinkEnabled,
        public_link_limit: $group.attributes.publicLinkLimit,
        feedback_enabled: $group.attributes.feedbackEnabled,
        tester_count: ($testers.data | length),
        tester_states: ($testers.data | map(.attributes.state // "UNKNOWN") | group_by(.) | map({key: .[0], value: length}) | from_entries),
        build_versions: ($builds.data | map(.attributes.version))
      }]')"
  done < <(jq -r '.data[].id' <<<"${groups_json}")

  jq -n \
    --arg checked_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --argjson groups "${report}" \
    '{checked_at: $checked_at, privacy: "No tester names or email addresses were requested.", groups: $groups}'
  exit 0
fi

group_json="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}")"
app_relationship="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}/app")"
actual_app_id="$(jq -r '.data.id // empty' <<<"${app_relationship}")"
if [[ "${actual_app_id}" != "${APP_ID}" ]]; then
  echo "error: configured beta group does not belong to the configured app" >&2
  exit 1
fi

testers_json="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}/betaTesters?limit=200&fields%5BbetaTesters%5D=state,inviteType")"
builds_json="$(api_get "https://api.appstoreconnect.apple.com/v1/betaGroups/${GROUP_ID}/builds?limit=200&fields%5Bbuilds%5D=version,processingState,uploadedDate,expired")"

jq -n \
  --argjson group "${group_json}" \
  --argjson testers "${testers_json}" \
  --argjson builds "${builds_json}" \
  --arg checked_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  '{
    checked_at: $checked_at,
    group: {
      name: $group.data.attributes.name,
      is_internal: $group.data.attributes.isInternalGroup,
      public_link_enabled: $group.data.attributes.publicLinkEnabled,
      public_link_limit_enabled: $group.data.attributes.publicLinkLimitEnabled,
      public_link_limit: $group.data.attributes.publicLinkLimit,
      feedback_enabled: $group.data.attributes.feedbackEnabled
    },
    testers: {
      count: ($testers.data | length),
      states: ($testers.data | map(.attributes.state // "UNKNOWN") | group_by(.) | map({key: .[0], value: length}) | from_entries),
      invite_types: ($testers.data | map(.attributes.inviteType // "UNKNOWN") | group_by(.) | map({key: .[0], value: length}) | from_entries)
    },
    builds: {
      count: ($builds.data | length),
      versions: ($builds.data | map({version: .attributes.version, state: .attributes.processingState, expired: .attributes.expired}))
    }
  }'
