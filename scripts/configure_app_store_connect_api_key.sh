#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <key-id> <issuer-id> <AuthKey_*.p8 path>" >&2
  exit 1
fi

KEY_ID="$1"
ISSUER_ID="$2"
SOURCE_KEY_PATH="$3"
CONFIG_DIR="${HOME}/Library/Application Support/BodyMode/AppStoreConnect"
CONFIG_PATH="${CONFIG_DIR}/config.plist"
INSTALLED_KEY_PATH="${CONFIG_DIR}/AuthKey_${KEY_ID}.p8"

if [[ ! "${KEY_ID}" =~ ^[A-Z0-9]+$ ]]; then
  echo "error: key ID must contain only uppercase letters and numbers" >&2
  exit 1
fi

if [[ ! "${ISSUER_ID}" =~ ^[0-9A-Fa-f-]+$ ]]; then
  echo "error: issuer ID must be a UUID" >&2
  exit 1
fi

if [[ ! -r "${SOURCE_KEY_PATH}" ]]; then
  echo "error: API key is not readable: ${SOURCE_KEY_PATH}" >&2
  exit 1
fi

if ! rg -q '^-----BEGIN PRIVATE KEY-----$' "${SOURCE_KEY_PATH}"; then
  echo "error: the selected file is not an App Store Connect private key" >&2
  exit 1
fi

mkdir -p "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"
install -m 600 "${SOURCE_KEY_PATH}" "${INSTALLED_KEY_PATH}"

plutil -create xml1 "${CONFIG_PATH}"
plutil -insert KeyID -string "${KEY_ID}" "${CONFIG_PATH}"
plutil -insert IssuerID -string "${ISSUER_ID}" "${CONFIG_PATH}"
plutil -insert KeyPath -string "${INSTALLED_KEY_PATH}" "${CONFIG_PATH}"
chmod 600 "${CONFIG_PATH}"

echo "App Store Connect API key configured for BodyMode uploads."
echo "Configuration: ${CONFIG_PATH}"
