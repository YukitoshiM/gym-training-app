#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bodymode-apple-key-test.XXXXXX")"
trap 'rm -rf "${TEMP_DIR}"' EXIT

ENV_FILE="${TEMP_DIR}/.env.local"
KEY_PATH="${TEMP_DIR}/AuthKey_TESTKEY123.p8"
print 'APPLE_CLIENT_ID=com.yukitoshim.gymtrainingapp' > "${ENV_FILE}"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "${KEY_PATH}" >/dev/null 2>&1

"${ROOT_DIR}/scripts/configure_sign_in_with_apple_key.sh" \
  --key-id TESTKEY123 \
  --key-path "${KEY_PATH}" \
  --env-file "${ENV_FILE}" >/dev/null

grep -q '^APPLE_KEY_ID=TESTKEY123$' "${ENV_FILE}"
grep -q '^APPLE_PRIVATE_KEY_PATH=.sign_in_with_apple/AuthKey_TESTKEY123.p8$' "${ENV_FILE}"
test -r "${TEMP_DIR}/.sign_in_with_apple/AuthKey_TESTKEY123.p8"
[[ "$(stat -f '%Lp' "${TEMP_DIR}/.sign_in_with_apple/AuthKey_TESTKEY123.p8")" == "600" ]]

print "Sign in with Apple key configuration test: PASS"
