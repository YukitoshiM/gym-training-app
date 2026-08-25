#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build/TestFlightPreflight"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release-iphoneos/GymTrainingApp.app"
BASE_REPORT_PATH="${ROOT_DIR}/.build/reports/testflight-preflight.txt"
STARTED_AT=$(date +%s)
RELEASE_ARTIFACT_PATH="${1:-${BODYMODE_RELEASE_ARTIFACT_PATH:-${BODYMODE_RELEASE_ARCHIVE_PATH:-}}}"
EXPECTED_AI_BASE_URL="${BODYMODE_EXPECTED_PRODUCTION_AI_URL:-https://bodymode-ai-gateway-production.bodymode-ai.workers.dev}"
preflight_failed=0

if [[ "$#" -gt 1 ]]; then
  printf 'Usage: %s [archive.xcarchive|exported.ipa]\n' "$0" >&2
  exit 64
fi

cd "${ROOT_DIR}"

record_error() {
  printf 'error: %s\n' "$1" >&2
  preflight_failed=1
}

plist_value() {
  local plist="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :${key}" "${plist}" 2>/dev/null || true
}

validate_https_url() {
  local plist="$1"
  local key="$2"
  local description="$3"
  local value

  value=$(plist_value "${plist}" "${key}")
  if [[ -z "${value}" ]]; then
    record_error "${description} must be nonempty"
  elif [[ ! "${value}" =~ ^https://[^/?#[:space:]]+([/?#][^[:space:]]*)?$ ]]; then
    record_error "${description} must be an absolute HTTPS URL"
  elif [[ "${value}" == *'@'* ]]; then
    record_error "${description} must not contain URL credentials"
  fi
}

validate_production_app() {
  local app_path="$1"
  local description="$2"
  local info_plist="${app_path}/Info.plist"
  local ai_url
  local ai_api_key
  local ai_configuration_version
  local session_token_mode
  local admob_app_id
  local admob_banner_id
  local admob_rewarded_id

  if [[ ! -f "${info_plist}" || ! -f "${app_path}/GymTrainingApp" ]]; then
    record_error "${description} is missing its Info.plist or executable"
    return
  fi

  validate_https_url "${info_plist}" BodyModeAIBaseURL "${description} AI URL"
  validate_https_url "${info_plist}" BodyModePrivacyPolicyURL "${description} privacy policy URL"
  validate_https_url "${info_plist}" BodyModeTermsURL "${description} terms URL"
  validate_https_url "${info_plist}" BodyModeSupportURL "${description} support URL"

  ai_url=$(plist_value "${info_plist}" BodyModeAIBaseURL)
  if [[ "${ai_url%/}" != "${EXPECTED_AI_BASE_URL%/}" ]]; then
    record_error "${description} AI URL must match the production gateway"
  fi
  if printf '%s' "${ai_url}" | grep -Eiq '(^|[./])localhost([/:]|$)|127\.0\.0\.1|trycloudflare\.com|\.ts\.net([/:]|$)'; then
    record_error "${description} AI URL must use a neutral managed gateway hostname"
  fi
  if strings "${app_path}/GymTrainingApp" | grep -Eiq 'trycloudflare\.com|[A-Za-z0-9-]+\.ts\.net'; then
    record_error "${description} executable must not contain a direct AI origin hostname"
  fi

  ai_api_key=$(plist_value "${info_plist}" BodyModeAIAPIKey)
  if [[ "${ai_api_key}" == "dev-local-key" ]]; then
    record_error "${description} AI API key must not use the development marker"
  fi

  ai_configuration_version=$(plist_value "${info_plist}" BodyModeAIConfigurationVersion)
  if [[ ! "${ai_configuration_version}" =~ ^[1-9][0-9]*$ ]]; then
    record_error "${description} AI configuration version must be a positive integer"
  fi

  session_token_mode=$(plist_value "${info_plist}" BodyModeAIUsesSessionTokens)
  if [[ "${session_token_mode}" != "YES" ]]; then
    record_error "${description} must enable AI session token mode"
  fi

  admob_app_id=$(plist_value "${info_plist}" GADApplicationIdentifier)
  admob_banner_id=$(plist_value "${info_plist}" BodyModeAdBannerUnitID)
  admob_rewarded_id=$(plist_value "${info_plist}" BodyModeAdRewardedUnitID)
  if [[ -z "${admob_app_id}" || -z "${admob_banner_id}" || -z "${admob_rewarded_id}" ]]; then
    record_error "${description} must contain the AdMob app, banner, and rewarded identifiers"
  elif [[ ! "${admob_app_id}" =~ ^ca-app-pub-[0-9]{16}~[0-9]{10}$ || \
    ! "${admob_banner_id}" =~ ^ca-app-pub-[0-9]{16}/[0-9]{10}$ || \
    ! "${admob_rewarded_id}" =~ ^ca-app-pub-[0-9]{16}/[0-9]{10}$ ]]; then
    record_error "${description} contains an invalid AdMob identifier format"
  elif [[ "${admob_app_id}" == ca-app-pub-3940256099942544* || \
    "${admob_banner_id}" == ca-app-pub-3940256099942544* || \
    "${admob_rewarded_id}" == ca-app-pub-3940256099942544* || \
    "${admob_app_id}" == ca-app-pub-0000000000000000* || \
    "${admob_banner_id}" == ca-app-pub-0000000000000000* || \
    "${admob_rewarded_id}" == ca-app-pub-0000000000000000* ]]; then
    record_error "${description} must use non-demo, non-placeholder AdMob identifiers"
  fi

}

validate_distribution_bundle() {
  local root_app="$1"
  local bundle
  local bundle_count=0
  local signature_details
  local entitlements
  local get_task_allow

  while IFS= read -r -d '' bundle; do
    bundle_count=$((bundle_count + 1))
    if ! codesign --verify --strict "${bundle}" >/dev/null 2>&1; then
      record_error "an app or extension in the exported IPA has an invalid signature"
      continue
    fi

    if ! signature_details=$(codesign -dvvv "${bundle}" 2>&1); then
      record_error "an app or extension in the exported IPA has no readable signature"
      continue
    fi
    if ! grep -Eq '^Authority=(Apple Distribution|iPhone Distribution):' <<<"${signature_details}"; then
      record_error "every app and extension in the exported IPA must use distribution signing"
    fi

    if ! entitlements=$(codesign -d --entitlements :- "${bundle}" 2>/dev/null); then
      record_error "an app or extension in the exported IPA has unreadable entitlements"
      continue
    fi
    get_task_allow=$(plutil -extract get-task-allow raw -o - - \
      <<<"${entitlements}" 2>/dev/null || true)
    if [[ "${get_task_allow}" == "true" || "${get_task_allow}" == "YES" || "${get_task_allow}" == "1" ]]; then
      record_error "get-task-allow must be absent or false in every exported app and extension"
    fi
  done < <(find "${root_app}" -type d \( -name '*.app' -o -name '*.appex' \) -print0)

  if [[ "${bundle_count}" -eq 0 ]]; then
    record_error "exported IPA has no signed app or extension bundles"
  fi
}

validate_release_artifact() {
  local archive_path="$1"
  local archive_app
  local export_root
  local exported_app

  if [[ ! -e "${archive_path}" ]]; then
    record_error "supplied release artifact does not exist"
    return
  fi

  if [[ "${archive_path}" == *.ipa ]]; then
    export_root=$(mktemp -d "${TMPDIR:-/tmp}/bodymode-ipa.XXXXXX")
    if ! unzip -q "${archive_path}" -d "${export_root}"; then
      record_error "supplied IPA cannot be extracted"
      return
    fi
    exported_app=$(find "${export_root}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)
    if [[ -z "${exported_app}" ]]; then
      record_error "supplied IPA does not contain an application"
      return
    fi
    validate_distribution_bundle "${exported_app}"
    validate_production_app "${exported_app}" "exported app"
    return
  fi

  archive_app=$(find "${archive_path}/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)
  if [[ -z "${archive_app}" ]]; then
    record_error "supplied archive does not contain an application"
    return
  fi

  # Automatic signing commonly gives the archive a development signature and
  # applies distribution signing during App Store export. Validate production
  # configuration here; pass the exported IPA to verify final signing.
  validate_production_app "${archive_app}" "archived app"
}

if [[ ! -s Config/Ads.local.xcconfig ]]; then
  record_error "Config/Ads.local.xcconfig is missing or empty"
fi
if [[ ! -s Config/AIService.local.xcconfig ]]; then
  record_error "Config/AIService.local.xcconfig is missing or empty"
fi

printf '[1/5] Running the base Release preflight (output is suppressed to protect secrets)\n'
base_status=0
REQUIRE_PRODUCTION_ADS=1 REQUIRE_SESSION_TOKENS=1 \
  ./scripts/testflight_preflight.sh >/dev/null 2>&1 || base_status=$?
if [[ "${base_status}" -ne 0 ]]; then
  record_error "base Release preflight failed; inspect its local report without sharing secret values"
fi

printf '[2/5] Validating release prerequisites\n'
prerequisite_status=0
if [[ "${BODYMODE_SKIP_RELEASE_PREREQUISITES:-0}" != "1" ]]; then
  ./scripts/release_prerequisites.sh >/dev/null 2>&1 || prerequisite_status=$?
fi
if [[ "${prerequisite_status}" -ne 0 ]]; then
  record_error "release prerequisites failed; run scripts/release_prerequisites.sh for details"
fi

printf '[3/5] Validating production URLs, AI mode, configuration version, and ads\n'
validate_production_app "${APP_PATH}" "built Release app"

printf '[4/5] Validating supported languages and English fallback\n'
localization_status=0
if [[ -n "${RELEASE_ARTIFACT_PATH}" && "${RELEASE_ARTIFACT_PATH}" != *.ipa ]]; then
  python3 ./scripts/audit_release_localizations.py "${RELEASE_ARTIFACT_PATH}" || localization_status=$?
else
  python3 ./scripts/audit_release_localizations.py || localization_status=$?
fi
if [[ "${localization_status}" -ne 0 ]]; then
  record_error "release localization audit failed"
fi

printf '[5/5] Validating optional release artifact\n'
if [[ -n "${RELEASE_ARTIFACT_PATH}" ]]; then
  validate_release_artifact "${RELEASE_ARTIFACT_PATH}"
  artifact_status="checked"
else
  artifact_status="not supplied"
fi

version="unavailable"
build="unavailable"
if [[ -f "${APP_PATH}/Info.plist" ]]; then
  version=$(plist_value "${APP_PATH}/Info.plist" CFBundleShortVersionString)
  build=$(plist_value "${APP_PATH}/Info.plist" CFBundleVersion)
  version=${version:-unavailable}
  build=${build:-unavailable}
fi
git_sha=$(git rev-parse --short=12 HEAD 2>/dev/null || printf 'unavailable')
if [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]; then
  git_state="dirty"
else
  git_state="clean"
fi
elapsed=$(($(date +%s) - STARTED_AT))

printf 'Version: %s (%s)\n' "${version}" "${build}"
printf 'Git SHA: %s\n' "${git_sha}"
printf 'Working tree: %s\n' "${git_state}"
printf 'Release artifact: %s\n' "${artifact_status}"
printf 'Elapsed: %ss\n' "${elapsed}"
printf 'Base preflight report: %s\n' "${BASE_REPORT_PATH}"

if [[ "${preflight_failed}" -ne 0 ]]; then
  printf 'Production release preflight: FAIL\n' >&2
  exit 1
fi

printf 'Production release preflight: PASS\n'
