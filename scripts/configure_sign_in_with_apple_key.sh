#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
ENV_FILE="${ROOT_DIR}/local_llm_server/.env.local"
KEY_ID=""
KEY_PATH=""
INSTALL_AGENT=false

usage() {
  print "Usage: $0 --key-id <10-character ID> --key-path <AuthKey_*.p8> [--env-file <path>] [--install-agent]"
}

while (( $# > 0 )); do
  case "$1" in
    --key-id)
      KEY_ID="${2:-}"
      shift 2
      ;;
    --key-path)
      KEY_PATH="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --install-agent)
      INSTALL_AGENT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "Unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "${KEY_ID}" =~ '^[A-Z0-9]{10}$' ]]; then
  print -u2 "The Apple key ID must contain exactly 10 uppercase letters or digits"
  exit 2
fi
if [[ ! -r "${KEY_PATH}" ]]; then
  print -u2 "The Sign in with Apple private key is not readable"
  exit 2
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  print -u2 "Server environment file not found: ${ENV_FILE}"
  exit 2
fi
if ! grep -q '^-----BEGIN PRIVATE KEY-----$' "${KEY_PATH}"; then
  print -u2 "The selected file is not an Apple PKCS#8 private key"
  exit 2
fi
if ! openssl pkey -in "${KEY_PATH}" -noout >/dev/null 2>&1; then
  print -u2 "The selected private key could not be validated"
  exit 2
fi
if ! openssl pkey -in "${KEY_PATH}" -text -noout 2>/dev/null | grep -q 'Private-Key: (256 bit)'; then
  print -u2 "The selected private key is not an Apple-compatible P-256 key"
  exit 2
fi

SERVER_DIR="${ENV_FILE:A:h}"
SECRET_DIR="${SERVER_DIR}/.sign_in_with_apple"
DESTINATION="${SECRET_DIR}/AuthKey_${KEY_ID}.p8"
RELATIVE_DESTINATION=".sign_in_with_apple/AuthKey_${KEY_ID}.p8"

install -d -m 700 "${SECRET_DIR}"
install -m 600 "${KEY_PATH}" "${DESTINATION}"

python3 - "${ENV_FILE}" "${KEY_ID}" "${RELATIVE_DESTINATION}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
updates = {
    "APPLE_KEY_ID": sys.argv[2],
    "APPLE_PRIVATE_KEY_PATH": sys.argv[3],
}
lines = path.read_text(encoding="utf-8").splitlines()
seen = set()
output = []
for line in lines:
    key = line.split("=", 1)[0] if "=" in line else ""
    if key in updates:
        output.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        output.append(line)
for key, value in updates.items():
    if key not in seen:
        output.append(f"{key}={value}")
path.write_text("\n".join(output) + "\n", encoding="utf-8")
PY
chmod 600 "${ENV_FILE}"

print "Sign in with Apple key configured locally."
print "Private key permissions: 600"

if [[ "${INSTALL_AGENT}" == true ]]; then
  "${ROOT_DIR}/scripts/install_local_ai_launch_agent.sh"
fi
