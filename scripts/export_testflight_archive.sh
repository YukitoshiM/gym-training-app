#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-${ROOT_DIR}/.build/BodyMode.xcarchive}"
EXPORT_PATH="${2:-${ROOT_DIR}/.build/TestFlightExport}"

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
  -allowProvisioningUpdates

echo "TestFlight export created at ${EXPORT_PATH}"
