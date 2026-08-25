#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASC_CONFIG_PATH="${BODYMODE_ASC_CONFIG_PATH:-${HOME}/Library/Application Support/BodyMode/AppStoreConnect/config.plist}"

cd "${ROOT_DIR}"

version="$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
build="$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)"
archive_path="${1:-${ROOT_DIR}/.build/BodyMode-AppStore-${version}-${build}.xcarchive}"
export_path="${2:-${ROOT_DIR}/.build/AppStoreExport-${version}-${build}}"

if [[ -e "${archive_path}" ]]; then
  echo "error: archive path already exists: ${archive_path}" >&2
  exit 1
fi
if [[ -e "${export_path}" ]]; then
  echo "error: export path already exists: ${export_path}" >&2
  exit 1
fi
if [[ ! -r "${ASC_CONFIG_PATH}" ]]; then
  echo "error: App Store Connect API config not found: ${ASC_CONFIG_PATH}" >&2
  echo "Run scripts/configure_app_store_connect_api_key.sh once." >&2
  exit 1
fi

key_id="$(plutil -extract KeyID raw -expect string "${ASC_CONFIG_PATH}")"
issuer_id="$(plutil -extract IssuerID raw -expect string "${ASC_CONFIG_PATH}")"
key_path="$(plutil -extract KeyPath raw -expect string "${ASC_CONFIG_PATH}")"
if [[ ! -r "${key_path}" ]]; then
  echo "error: configured App Store Connect API key is not readable" >&2
  exit 1
fi

echo "[1/5] Validate production backend and public legal pages"
"${ROOT_DIR}/scripts/release_prerequisites.sh"

echo "[2/5] Generate Xcode project"
xcodegen generate

echo "[3/5] Create App Store archive for BodyMode ${version} (${build})"
xcodebuild archive \
  -project GymTrainingApp.xcodeproj \
  -scheme GymTrainingApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${archive_path}" \
  -clonedSourcePackagesDirPath "${ROOT_DIR}/.build/SourcePackages" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${key_path}" \
  -authenticationKeyID "${key_id}" \
  -authenticationKeyIssuerID "${issuer_id}"

echo "[4/5] Export with App Store distribution signing"
"${ROOT_DIR}/scripts/export_testflight_archive.sh" "${archive_path}" "${export_path}"

ipa_path="$(find "${export_path}" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
if [[ -z "${ipa_path}" ]]; then
  echo "error: App Store export did not produce an IPA" >&2
  exit 1
fi

echo "[5/5] Validate production configuration, signatures, and privacy manifests"
BODYMODE_SKIP_RELEASE_PREREQUISITES=1 \
  "${ROOT_DIR}/scripts/release_production_preflight.sh" "${ipa_path}"

echo "App Store candidate is ready locally."
echo "Archive: ${archive_path}"
echo "IPA: ${ipa_path}"
echo "No upload was performed."
