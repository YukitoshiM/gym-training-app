#!/usr/bin/env bash
set -euo pipefail

WATCH_ID="${BODYMODE_WATCH_SIMULATOR_ID:-BA7E905A-2972-457A-8F4B-90B24C449DC3}"
BUNDLE_ID="com.yukitoshim.gymtrainingapp.watchkitapp"
if [[ -d "build/Debug-watchsimulator/GymTrainingWatchApp.app" ]]; then
  APP_PATH="build/Debug-watchsimulator/GymTrainingWatchApp.app"
else
  APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-watchsimulator/GymTrainingWatchApp.app' -print | tail -1)"
fi
OUTPUT_DIR="docs/localization/ui-smoke"

if [[ -z "$APP_PATH" ]]; then
  echo "GymTrainingWatchApp.app not found. Build the watch simulator target first." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
xcrun simctl boot "$WATCH_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$WATCH_ID" -b >/dev/null
while IFS='|' read -r name language locale; do
  xcrun simctl terminate "$WATCH_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$WATCH_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$WATCH_ID" "$APP_PATH"
  xcrun simctl launch --terminate-running-process "$WATCH_ID" "$BUNDLE_ID" \
    -AppleLanguages "($language)" \
    -AppleLocale "$locale" >/dev/null
  sleep 2
  xcrun simctl io "$WATCH_ID" screenshot "$OUTPUT_DIR/$name-watch.png" >/dev/null
  echo "$name watch: captured"
done <<'LOCALES'
ja|ja|ja_JP
en-US|en|en_US
de-DE|de|de_DE
ar-SA|ar|ar_SA
LOCALES

xcrun simctl terminate "$WATCH_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl shutdown "$WATCH_ID" >/dev/null 2>&1 || true
