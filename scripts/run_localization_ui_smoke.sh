#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${BODYMODE_SIMULATOR_ID:-9CEFD46A-36AB-4008-B820-EE8B9BE727AC}"
BUNDLE_ID="com.yukitoshim.gymtrainingapp"
APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/GymTrainingApp.app' -print | tail -1)"
OUTPUT_DIR="docs/localization/ui-smoke"

if [[ -z "$APP_PATH" ]]; then
  echo "GymTrainingApp.app not found. Build the simulator target first." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
while IFS='|' read -r name language locale; do
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$DEVICE_ID" "$APP_PATH"
  xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_ID" \
    -AppleLanguages "($language)" \
    -AppleLocale "$locale" \
    --reset-ui-test-data \
    --seed-alpha-ui-test-plan \
    --stub-ai-trainer \
    --disable-app-tour \
    --force-dark-appearance >/dev/null
  sleep 2
  xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/$name-iphone.png" >/dev/null
  echo "$name: captured"
done <<'LOCALES'
ja|ja|ja_JP
en-US|en|en_US
zh-Hans|zh-Hans|zh_CN
de-DE|de|de_DE
ar-SA|ar|ar_SA
LOCALES

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
