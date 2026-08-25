#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASC_CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"
DERIVED_DATA_PATH="${BODYMODE_SIDELOAD_DERIVED_DATA:-${ROOT_DIR}/.build/sideload/DerivedData}"
IPHONE_DEVICE="${BODYMODE_IPHONE_DEVICE:-}"
WATCH_DEVICE="${BODYMODE_WATCH_DEVICE:-}"

usage() {
  printf 'Usage: %s --iphone <CoreDevice ID or name> [--watch <CoreDevice ID or name>]\n' "$0" >&2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --iphone)
      IPHONE_DEVICE="${2:-}"
      shift 2
      ;;
    --watch)
      WATCH_DEVICE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ -z "${IPHONE_DEVICE}" ]]; then
  usage
  exit 64
fi

if [[ ! -f "${ASC_CONFIG_PATH}" ]]; then
  printf 'error: App Store Connect API configuration not found: %s\n' "${ASC_CONFIG_PATH}" >&2
  exit 1
fi

key_id="$(plutil -extract KeyID raw -expect string "${ASC_CONFIG_PATH}")"
issuer_id="$(plutil -extract IssuerID raw -expect string "${ASC_CONFIG_PATH}")"
key_path="$(plutil -extract KeyPath raw -expect string "${ASC_CONFIG_PATH}")"
if [[ ! -r "${key_path}" ]]; then
  printf 'error: App Store Connect API key is not readable: %s\n' "${key_path}" >&2
  exit 1
fi

cd "${ROOT_DIR}"

printf '[1/4] Build and sign BodyMode without relying on the Xcode Accounts session\n'
xcodebuild \
  -project GymTrainingApp.xcodeproj \
  -scheme GymTrainingApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${key_path}" \
  -authenticationKeyID "${key_id}" \
  -authenticationKeyIssuerID "${issuer_id}" \
  build

iphone_app="${DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/GymTrainingApp.app"
watch_app="${DERIVED_DATA_PATH}/Build/Products/Debug-watchos/GymTrainingWatchApp.app"
if [[ ! -d "${iphone_app}" ]]; then
  printf 'error: signed iPhone app not found: %s\n' "${iphone_app}" >&2
  exit 1
fi

printf '[2/4] Install iPhone app\n'
xcrun devicectl device install app \
  --device "${IPHONE_DEVICE}" \
  --timeout 90 \
  "${iphone_app}"

printf '[3/4] Launch iPhone app\n'
xcrun devicectl device process launch \
  --device "${IPHONE_DEVICE}" \
  --timeout 30 \
  com.yukitoshim.gymtrainingapp

if [[ -n "${WATCH_DEVICE}" ]]; then
  if [[ ! -d "${watch_app}" ]]; then
    printf 'error: signed Watch app not found: %s\n' "${watch_app}" >&2
    exit 1
  fi
  printf '[4/4] Install Watch app\n'
  if ! xcrun devicectl device install app \
    --device "${WATCH_DEVICE}" \
    --timeout 90 \
    "${watch_app}"; then
    printf 'Watch tunnel failed once; retrying in 3 seconds.\n' >&2
    sleep 3
    xcrun devicectl device install app \
      --device "${WATCH_DEVICE}" \
      --timeout 90 \
      "${watch_app}"
  fi
else
  printf '[4/4] Watch install skipped (no --watch device)\n'
fi

printf 'BodyMode sideload completed. Existing app data is preserved by bundle identifier.\n'
