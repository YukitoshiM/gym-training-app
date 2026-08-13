#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build/TestFlightPreflight"
REPORT_DIR="${ROOT_DIR}/.build/reports"
REPORT_PATH="${REPORT_DIR}/testflight-preflight.txt"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release-iphoneos/GymTrainingApp.app"
WATCH_APP_PATH="${APP_PATH}/Watch/GymTrainingWatchApp.app"
WATCH_WIDGET_PATH="${WATCH_APP_PATH}/PlugIns/GymTrainingWatchWidget.appex"

mkdir -p "${REPORT_DIR}"
exec > >(tee "${REPORT_PATH}") 2>&1

cd "${ROOT_DIR}"

echo "[1/8] Source and project checks"
git diff --check
plutil -lint Shared/PrivacyInfo.xcprivacy
plutil -lint GymTrainingApp/Info.plist GymTrainingWatchApp/Info.plist GymTrainingWatchWidget/Info.plist
plutil -lint scripts/TestFlightExportOptions.plist
plutil -lint scripts/TestFlightUploadOptions.plist
swift scripts/validate_theme_contrast.swift

test -f GymTrainingApp/Support/ProtectedDataStore.swift
grep -q "completeFileProtectionUntilFirstUserAuthentication" GymTrainingApp/Support/ProtectedDataStore.swift
grep -q "isExcludedFromBackup" GymTrainingApp/Support/ProtectedDataStore.swift
grep -q "SecureSettingsStore" GymTrainingApp/Domain/AIModels.swift
grep -q "kSecClassGenericPassword" GymTrainingApp/Domain/AIModels.swift
grep -q "AICachedAccessToken" GymTrainingApp/Domain/AIModels.swift
grep -q 'POST("/v1/auth/token"' local_llm_server/main.py || grep -q '@app.post("/v1/auth/token"' local_llm_server/main.py

iphone_screenshot_count=0
for screenshot in docs/app-store/screenshots/*.png; do
  iphone_screenshot_count=$((iphone_screenshot_count + 1))
  [[ "$(sips -g pixelWidth "${screenshot}" | awk '/pixelWidth/ {print $2}')" == "1320" ]]
  [[ "$(sips -g pixelHeight "${screenshot}" | awk '/pixelHeight/ {print $2}')" == "2868" ]]
  [[ "$(sips -g hasAlpha "${screenshot}" | awk '/hasAlpha/ {print $2}')" == "no" ]]
done
[[ "${iphone_screenshot_count}" -ge 1 && "${iphone_screenshot_count}" -le 10 ]]

watch_screenshot_count=0
for screenshot in docs/app-store/watch-screenshots/*.png; do
  watch_screenshot_count=$((watch_screenshot_count + 1))
  [[ "$(sips -g pixelWidth "${screenshot}" | awk '/pixelWidth/ {print $2}')" == "416" ]]
  [[ "$(sips -g pixelHeight "${screenshot}" | awk '/pixelHeight/ {print $2}')" == "496" ]]
  [[ "$(sips -g hasAlpha "${screenshot}" | awk '/hasAlpha/ {print $2}')" == "no" ]]
done
[[ "${watch_screenshot_count}" -ge 1 && "${watch_screenshot_count}" -le 10 ]]

if rg -n --glob '*.{swift,plist,yml,json}' \
  --glob '!GymTrainingApp/Domain/AIModels.swift' \
  --glob '!local_llm_server/**' \
  'sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' .; then
  echo "error: possible committed secret found" >&2
  exit 1
fi

if git ls-files --error-unmatch Config/AIService.local.xcconfig >/dev/null 2>&1; then
  echo "error: Config/AIService.local.xcconfig must not be tracked by Git" >&2
  exit 1
fi

if git ls-files --error-unmatch Config/Ads.local.xcconfig >/dev/null 2>&1; then
  echo "error: Config/Ads.local.xcconfig must not be tracked by Git" >&2
  exit 1
fi

echo "[2/8] Generate Xcode project"
xcodegen generate

echo "[3/8] Unsigned Release build"
xcodebuild \
  -project GymTrainingApp.xcodeproj \
  -scheme GymTrainingApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${ROOT_DIR}/.build/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[4/8] Embedded app and privacy manifests"
test -d "${APP_PATH}"
test -d "${WATCH_APP_PATH}"
test -d "${WATCH_WIDGET_PATH}"

for manifest in \
  "${APP_PATH}/PrivacyInfo.xcprivacy" \
  "${WATCH_APP_PATH}/PrivacyInfo.xcprivacy" \
  "${APP_PATH}/Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy" \
  "${APP_PATH}/Frameworks/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy"; do
  test -f "${manifest}"
  plutil -lint "${manifest}"
done

test -d "${APP_PATH}/Frameworks/GoogleMobileAds.framework"
test -d "${APP_PATH}/Frameworks/UserMessagingPlatform.framework"
test ! -d "${WATCH_APP_PATH}/Frameworks/GoogleMobileAds.framework"
test ! -d "${WATCH_APP_PATH}/Frameworks/UserMessagingPlatform.framework"
test ! -d "${WATCH_WIDGET_PATH}/Frameworks/GoogleMobileAds.framework"
test ! -d "${WATCH_WIDGET_PATH}/Frameworks/UserMessagingPlatform.framework"

echo "[5/8] Secrets and transport security"
if strings "${APP_PATH}/GymTrainingApp" | grep "dev-local-key" >/dev/null; then
  echo "error: development AI key is present in the Release binary" >&2
  exit 1
fi

AI_BASE_URL=$(/usr/libexec/PlistBuddy -c 'Print :BodyModeAIBaseURL' "${APP_PATH}/Info.plist" 2>/dev/null || true)
AI_API_KEY=$(/usr/libexec/PlistBuddy -c 'Print :BodyModeAIAPIKey' "${APP_PATH}/Info.plist" 2>/dev/null || true)
AI_CONFIGURATION_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :BodyModeAIConfigurationVersion' "${APP_PATH}/Info.plist" 2>/dev/null || true)
if [[ -n "${AI_BASE_URL}" && -z "${AI_API_KEY}" ]] || [[ -z "${AI_BASE_URL}" && -n "${AI_API_KEY}" ]]; then
    echo "error: AI Base URL and API key must either both be set or both be empty" >&2
    exit 1
fi
if [[ -n "${AI_BASE_URL}" && "${AI_BASE_URL}" != https://* ]]; then
    echo "error: Release AI Base URL must use HTTPS" >&2
    exit 1
fi
if [[ -n "${AI_BASE_URL}" && ! "${AI_CONFIGURATION_VERSION}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: bundled AI configuration requires a positive version for safe migrations" >&2
    exit 1
fi
if [[ "${REQUIRE_SESSION_TOKENS:-0}" == "1" ]] && \
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :BodyModeAIUsesSessionTokens' "${APP_PATH}/Info.plist" 2>/dev/null || true)" != "YES" ]]; then
  echo "error: production AI configuration must enable session tokens" >&2
  exit 1
fi

ADMOB_APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :GADApplicationIdentifier' "${APP_PATH}/Info.plist" 2>/dev/null || true)
ADMOB_BANNER_ID=$(/usr/libexec/PlistBuddy -c 'Print :BodyModeAdBannerUnitID' "${APP_PATH}/Info.plist" 2>/dev/null || true)
if [[ -z "${ADMOB_APP_ID}" || -z "${ADMOB_BANNER_ID}" ]]; then
  echo "error: Release AdMob app ID and banner unit ID must both be configured" >&2
  exit 1
fi
if [[ "${ADMOB_APP_ID}" != ca-app-pub-*~* || "${ADMOB_BANNER_ID}" != ca-app-pub-*/* ]]; then
  echo "error: invalid AdMob app ID or banner unit ID" >&2
  exit 1
fi
if [[ "${ADMOB_APP_ID}" == "ca-app-pub-3940256099942544~1458002511" ]]; then
  if [[ "${REQUIRE_PRODUCTION_ADS:-0}" == "1" ]]; then
    echo "error: Google demo AdMob IDs cannot be used for App Store production" >&2
    exit 1
  fi
  echo "warning: Release currently uses Google demo ads; replace them before App Store production"
fi

SKAD_COUNT=$(/usr/libexec/PlistBuddy -c 'Print :SKAdNetworkItems' "${APP_PATH}/Info.plist" 2>/dev/null | grep -c 'Dict' || true)
if [[ "${SKAD_COUNT}" -lt 1 ]]; then
  echo "error: SKAdNetworkItems are missing" >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :NSUserTrackingUsageDescription' "${APP_PATH}/Info.plist" >/dev/null 2>&1; then
  echo "error: ATT usage text is present even though BodyMode does not request cross-app tracking" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsArbitraryLoads' "${APP_PATH}/Info.plist" 2>/dev/null || true)" == "true" ]]; then
  echo "error: NSAllowsArbitraryLoads is enabled" >&2
  exit 1
fi

echo "[6/8] Export compliance and storage protection"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "${APP_PATH}/Info.plist")" != "false" ]]; then
  echo "error: ITSAppUsesNonExemptEncryption must be false" >&2
  exit 1
fi

if ! nm -j "${APP_PATH}/GymTrainingApp" | grep "ProtectedDataStore" >/dev/null; then
  echo "error: protected record storage is missing from the Release binary" >&2
  exit 1
fi

echo "[7/8] Optional UI regression suite"
if [[ "${RUN_UI_TESTS:-0}" == "1" ]]; then
  xcodebuild test \
    -project GymTrainingApp.xcodeproj \
    -scheme GymTrainingApp \
    -destination "${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}" \
    -clonedSourcePackagesDirPath "${ROOT_DIR}/.build/SourcePackages" \
    -only-testing:GymTrainingAppUITests/WorkoutFlowUITests \
    -only-testing:GymTrainingAppUITests/BodyAndNutritionUITests \
    -only-testing:GymTrainingAppUITests/IntegrationAndHealthUITests \
    -only-testing:GymTrainingAppUITests/SettingsAndAccessibilityUITests \
    -only-testing:GymTrainingAppUITests/AITrainerUITests
else
  echo "Skipped. Run with RUN_UI_TESTS=1 to include the iPhone UI suite."
fi

echo "[8/8] Version and unresolved owner inputs"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Info.plist")

for key in BodyModePrivacyPolicyURL BodyModeTermsURL BodyModeSupportURL BodyModeSupportEmail; do
  value=$(/usr/libexec/PlistBuddy -c "Print :${key}" "${APP_PATH}/Info.plist" 2>/dev/null || true)
  if [[ -z "${value}" ]]; then
    echo "warning: ${key} still requires an owner-provided public value"
  fi
done

echo "TestFlight preflight passed for BodyMode ${VERSION} (${BUILD_NUMBER})."
echo "Report: ${REPORT_PATH}"
