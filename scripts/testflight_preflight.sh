#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build/TestFlightPreflight"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release-iphoneos/GymTrainingApp.app"
WATCH_APP_PATH="${APP_PATH}/Watch/GymTrainingWatchApp.app"

cd "${ROOT_DIR}"

plutil -lint Shared/PrivacyInfo.xcprivacy
xcodegen generate

xcodebuild \
  -project GymTrainingApp.xcodeproj \
  -scheme GymTrainingApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

for manifest in "${APP_PATH}/PrivacyInfo.xcprivacy" "${WATCH_APP_PATH}/PrivacyInfo.xcprivacy"; do
  test -f "${manifest}"
  plutil -lint "${manifest}"
done

if strings "${APP_PATH}/GymTrainingApp" | grep -q "dev-local-key"; then
  echo "error: development AI key is present in the Release binary" >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSAllowsArbitraryLoads" "${APP_PATH}/Info.plist" >/dev/null 2>&1; then
  echo "error: NSAllowsArbitraryLoads is enabled" >&2
  exit 1
fi

BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Info.plist")

echo "TestFlight preflight passed for BodyMode ${VERSION} (${BUILD_NUMBER})."
