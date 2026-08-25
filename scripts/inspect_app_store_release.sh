#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${BODYMODE_APP_ID:-6799871527}"
VERSION="${1:-$(awk '/MARKETING_VERSION:/ {print $2; exit}' "${ROOT_DIR}/project.yml")}"
CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"

if [[ ! -r "${CONFIG_PATH}" ]]; then
  echo "error: App Store Connect API config not found: ${CONFIG_PATH}" >&2
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
optional_response_path="$(mktemp /tmp/bodymode-asc-response.XXXXXX)"
trap 'rm -f "${signature_path}" "${optional_response_path}"' EXIT

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

api_get_optional() {
  local status
  status="$(curl --silent --show-error -o "${optional_response_path}" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" "$1")"
  if [[ "${status}" == "200" ]]; then
    cat "${optional_response_path}"
  elif [[ "${status}" != "404" ]]; then
    echo "error: App Store Connect returned HTTP ${status}" >&2
    jq -r '.errors[]? | [.code, .title, .detail] | @tsv' "${optional_response_path}" >&2
    return 1
  fi
}

versions_json="$(api_get "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appStoreVersions?limit=50")"
version_id="$(jq -r --arg version "${VERSION}" '.data[] | select(.attributes.platform == "IOS" and .attributes.versionString == $version) | .id' <<<"${versions_json}" | head -1)"
app_json="$(api_get "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}")"
app_infos_json="$(api_get "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appInfos?limit=50")"

echo "BodyMode App Store release audit"
echo "App: $(jq -r '.data.attributes.name // "unknown"' <<<"${app_json}")"
echo "Bundle ID: $(jq -r '.data.attributes.bundleId // "unknown"' <<<"${app_json}")"
echo "Primary locale: $(jq -r '.data.attributes.primaryLocale // "missing"' <<<"${app_json}")"
echo "Content rights: $(jq -r '.data.attributes.contentRightsDeclaration // "missing"' <<<"${app_json}")"
echo "App info records: $(jq '.data | length' <<<"${app_infos_json}")"
while IFS=$'\t' read -r info_state info_id; do
  [[ -n "${info_id}" ]] || continue
  info_localizations_json="$(api_get "https://api.appstoreconnect.apple.com/v1/appInfos/${info_id}/appInfoLocalizations?limit=50")"
  primary_category_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/appInfos/${info_id}/primaryCategory")"
  printf '  app info state=%s, localizations=%s\n' \
    "${info_state:-UNKNOWN}" \
    "$(jq -r '[.data[].attributes.locale] | join(",")' <<<"${info_localizations_json}")"
  printf '  primary category=%s\n' \
    "$(if [[ -n "${primary_category_json}" ]]; then jq -r '.data.id // "missing"' <<<"${primary_category_json}"; else echo missing; fi)"
  age_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/appInfos/${info_id}/ageRatingDeclaration")"
  if [[ -n "${age_json}" ]]; then
    unanswered_age_fields="$(jq '[.data.attributes | to_entries[] | select(.key | IN(
      "advertising", "healthOrWellnessTopics", "alcoholTobaccoOrDrugUseOrReferences",
      "contests", "gambling", "gamblingSimulated", "gunsOrOtherWeapons", "lootBox",
      "medicalOrTreatmentInformation", "messagingAndChat", "parentalControls", "ageAssurance",
      "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
      "socialMedia", "socialMediaAgeRestricted", "horrorOrFearThemes", "matureOrSuggestiveThemes",
      "unrestrictedWebAccess", "userGeneratedContent", "violenceCartoonOrFantasy",
      "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic"
    )) | select(.value == null)] | length' <<<"${age_json}")"
    printf '  age rating=%s, unanswered=%s\n' \
      "$(jq -r --arg id "${info_id}" '.data[] | select(.id == $id) | .attributes.appStoreAgeRating // "missing"' <<<"${app_infos_json}")" \
      "${unanswered_age_fields}"
  fi
done < <(jq -r '.data[] | [.attributes.appStoreState // "UNKNOWN", .id] | @tsv' <<<"${app_infos_json}")
echo "Requested version: ${VERSION}"
echo "Existing version records: $(jq '.data | length' <<<"${versions_json}")"
jq -r '.data[] | "  \(.attributes.platform // "UNKNOWN") \(.attributes.versionString // "missing"): \(.attributes.appVersionState // .attributes.appStoreState // "UNKNOWN")"' <<<"${versions_json}"

if [[ -z "${version_id}" ]]; then
  echo "Version record: missing"
  echo "Next action: create iOS version ${VERSION} in App Store Connect."
  exit 2
fi

state="$(jq -r --arg id "${version_id}" '.data[] | select(.id == $id) | (.attributes.appVersionState // .attributes.appStoreState // "UNKNOWN")' <<<"${versions_json}")"
copyright="$(jq -r --arg id "${version_id}" '.data[] | select(.id == $id) | .attributes.copyright // empty' <<<"${versions_json}")"
release_type="$(jq -r --arg id "${version_id}" '.data[] | select(.id == $id) | .attributes.releaseType // "missing"' <<<"${versions_json}")"
uses_idfa="$(jq -r --arg id "${version_id}" '.data[] | select(.id == $id) | if .attributes | has("usesIdfa") then .attributes.usesIdfa else "missing" end' <<<"${versions_json}")"
echo "Version record: present"
echo "Version state: ${state}"
echo "Release type: ${release_type}"
echo "Uses IDFA: ${uses_idfa}"
echo "Copyright: $([[ -n "${copyright}" ]] && echo configured || echo missing)"

build_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/appStoreVersions/${version_id}/build")"
if [[ -n "${build_json}" ]]; then
  build_number="$(jq -r '.data.attributes.version // empty' <<<"${build_json}")"
else
  build_number=""
fi
echo "Selected build: ${build_number:-missing}"
if [[ -n "${build_json}" ]]; then
  echo "Uses non-exempt encryption: $(jq -r 'if .data.attributes | has("usesNonExemptEncryption") then .data.attributes.usesNonExemptEncryption else "missing" end' <<<"${build_json}")"
fi

price_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appPriceSchedule")"
if [[ -z "${price_json}" ]]; then
  echo "Price: missing"
else
  prices_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/appPriceSchedules/${APP_ID}/manualPrices?include=appPricePoint&limit=200")"
  current_price="$(jq -r '
    (.included // [] | map(select(.type == "appPricePoints")) | map({key: .id, value: .attributes.customerPrice}) | from_entries) as $points
    | [.data[] | select(.attributes.endDate == null) | $points[.relationships.appPricePoint.data.id]]
    | first // "missing"
  ' <<<"${prices_json}")"
  echo "Price: ${current_price}"
fi

availability_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appAvailabilityV2")"
if [[ -z "${availability_json}" ]]; then
  echo "Availability: missing"
else
  availability_id="$(jq -r '.data.id' <<<"${availability_json}")"
  territory_json="$(api_get "https://api.appstoreconnect.apple.com/v2/appAvailabilities/${availability_id}/territoryAvailabilities?limit=200&include=territory")"
  echo "Availability: $(jq '[.data[] | select(.attributes.available == true)] | length' <<<"${territory_json}") territories"
  eu_available="$(jq -r '
    ["AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA","DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD","POL","PRT","ROU","SVK","SVN","ESP","SWE"] as $eu
    | [.data[]
      | select(.attributes.available == true)
      | .relationships.territory.data.id
      | select(. as $id | $eu | index($id))]
    | join(",")
  ' <<<"${territory_json}")"
  if [[ -n "${eu_available}" ]]; then
    echo "error: EU territories are still enabled: ${eu_available}" >&2
    exit 3
  fi
  echo "EU27 availability: excluded"
  echo "Future territories automatically enabled: $(jq -r '.data.attributes.availableInNewTerritories' <<<"${availability_json}")"
fi

localizations_json="$(api_get "https://api.appstoreconnect.apple.com/v1/appStoreVersions/${version_id}/appStoreVersionLocalizations?limit=50")"
localization_count="$(jq '.data | length' <<<"${localizations_json}")"
echo "Version localizations: ${localization_count}"

while IFS=$'\t' read -r locale localization_id; do
  [[ -n "${locale}" ]] || continue
  sets_json="$(api_get "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/${localization_id}/appScreenshotSets?limit=50")"
  set_count="$(jq '.data | length' <<<"${sets_json}")"
  screenshot_count=0
  while IFS= read -r set_id; do
    [[ -n "${set_id}" ]] || continue
    screenshots_json="$(api_get "https://api.appstoreconnect.apple.com/v1/appScreenshotSets/${set_id}/appScreenshots?limit=50")"
    screenshot_count="$((screenshot_count + $(jq '.data | length' <<<"${screenshots_json}")))"
  done < <(jq -r '.data[].id' <<<"${sets_json}")
  printf '  %s: screenshot sets=%s, screenshots=%s\n' "${locale}" "${set_count}" "${screenshot_count}"
done < <(jq -r '.data[] | [.attributes.locale, .id] | @tsv' <<<"${localizations_json}")

review_json="$(api_get_optional "https://api.appstoreconnect.apple.com/v1/appStoreVersions/${version_id}/appStoreReviewDetail")"
if [[ -z "${review_json}" ]]; then
  echo "Review detail: missing"
else
  missing_review_fields="$(jq -r '[
    .data.attributes.contactFirstName,
    .data.attributes.contactLastName,
    .data.attributes.contactPhone,
    .data.attributes.contactEmail,
    .data.attributes.notes
  ] | map(select(. == null or . == "")) | length' <<<"${review_json}")"
  demo_required="$(jq -r '.data.attributes.demoAccountRequired // false' <<<"${review_json}")"
  echo "Review detail: present"
  echo "Review fields missing: ${missing_review_fields}"
  echo "Demo account required: ${demo_required}"
fi

echo "Manual App Store Connect checks (not exposed by the public API):"
echo "  App Privacy answers published"
echo "  Regulated medical device: No"
echo "  Account Holder DSA non-trader / no-EU-distribution declaration completed"
