#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-${ROOT_DIR}/.build/BodyMode.xcarchive}"
EXPORT_PATH="${2:-${ROOT_DIR}/.build/TestFlightExport}"
ASC_CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"
authentication_args=()

if [[ -f "${ASC_CONFIG_PATH}" ]]; then
  APP_STORE_CONNECT_KEY_ID="$(plutil -extract KeyID raw -expect string "${ASC_CONFIG_PATH}")"
  APP_STORE_CONNECT_ISSUER_ID="$(plutil -extract IssuerID raw -expect string "${ASC_CONFIG_PATH}")"
  APP_STORE_CONNECT_KEY_PATH="$(plutil -extract KeyPath raw -expect string "${ASC_CONFIG_PATH}")"
  if [[ ! -r "${APP_STORE_CONNECT_KEY_PATH}" ]]; then
    echo "error: App Store Connect API key is not readable: ${APP_STORE_CONNECT_KEY_PATH}" >&2
    exit 1
  fi
  authentication_args=(
    -authenticationKeyPath "${APP_STORE_CONNECT_KEY_PATH}"
    -authenticationKeyID "${APP_STORE_CONNECT_KEY_ID}"
    -authenticationKeyIssuerID "${APP_STORE_CONNECT_ISSUER_ID}"
  )
  echo "Using App Store Connect API key ${APP_STORE_CONNECT_KEY_ID}."
else
  echo "warning: App Store Connect API key is not configured; using the Apple Account stored in Xcode" >&2
fi

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "error: archive not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

if [[ -e "${EXPORT_PATH}" ]]; then
  echo "error: export path already exists: ${EXPORT_PATH}" >&2
  exit 1
fi

plutil -lint "${ROOT_DIR}/scripts/TestFlightExportOptions.plist"

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${ROOT_DIR}/scripts/TestFlightExportOptions.plist" \
  -allowProvisioningUpdates \
  "${authentication_args[@]}"

echo "TestFlight export created at ${EXPORT_PATH}"
