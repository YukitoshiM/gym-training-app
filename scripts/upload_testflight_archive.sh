#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-${ROOT_DIR}/.build/BodyMode-TestFlight.xcarchive}"
OPTIONS_PATH="${ROOT_DIR}/scripts/TestFlightUploadOptions.plist"
ASC_CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"

authentication_args=()

load_api_key_from_config() {
  [[ -f "${ASC_CONFIG_PATH}" ]] || return 1

  APP_STORE_CONNECT_KEY_ID="$(plutil -extract KeyID raw -expect string "${ASC_CONFIG_PATH}")"
  APP_STORE_CONNECT_ISSUER_ID="$(plutil -extract IssuerID raw -expect string "${ASC_CONFIG_PATH}")"
  APP_STORE_CONNECT_KEY_PATH="$(plutil -extract KeyPath raw -expect string "${ASC_CONFIG_PATH}")"
}

configure_authentication() {
  if [[ -n "${APP_STORE_CONNECT_KEY_ID:-}" || -n "${APP_STORE_CONNECT_ISSUER_ID:-}" || -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
    if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" || -z "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
      echo "error: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, and APP_STORE_CONNECT_KEY_PATH must all be set" >&2
      exit 1
    fi
  elif ! load_api_key_from_config; then
    echo "warning: App Store Connect API key is not configured; falling back to the Apple Account stored in Xcode" >&2
    echo "         Run scripts/configure_app_store_connect_api_key.sh once to avoid repeated Xcode sign-in." >&2
    return
  fi

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
}

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "error: archive not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

plutil -lint "${OPTIONS_PATH}"
configure_authentication

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${OPTIONS_PATH}" \
  -allowProvisioningUpdates \
  "${authentication_args[@]}"

echo "TestFlight upload submitted to App Store Connect"
