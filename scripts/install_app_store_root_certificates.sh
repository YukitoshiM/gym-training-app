#!/usr/bin/env bash

set -euo pipefail

DESTINATION="${1:-${HOME}/Library/Application Support/BodyMode/AppStoreRootCertificates}"
mkdir -p "${DESTINATION}"
chmod 700 "${DESTINATION}"

download_certificate() {
  local name="$1"
  local url="https://www.apple.com/certificateauthority/${name}.cer"
  local temporary
  temporary=$(mktemp "${DESTINATION}/.${name}.XXXXXX")
  trap 'rm -f "${temporary}"' RETURN
  curl --fail --location --silent --show-error --max-time 30 "${url}" --output "${temporary}"
  openssl x509 -inform DER -in "${temporary}" -noout -subject >/dev/null
  chmod 600 "${temporary}"
  mv "${temporary}" "${DESTINATION}/${name}.cer"
  trap - RETURN
}

download_certificate "AppleRootCA-G2"
download_certificate "AppleRootCA-G3"

count=$(find "${DESTINATION}" -maxdepth 1 -type f -name 'AppleRootCA-G*.cer' | wc -l | tr -d ' ')
if [[ "${count}" -lt 2 ]]; then
  echo "error: expected Apple G2 and G3 root certificates" >&2
  exit 1
fi

echo "Installed ${count} Apple root certificates in ${DESTINATION}"
echo "Set APP_STORE_ROOT_CERTIFICATES_PATH to this directory."
