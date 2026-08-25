#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
GATEWAY_DIR="${REPO_ROOT}/cloudflare_ai_gateway"
LOCAL_ENV="${REPO_ROOT}/local_llm_server/.env.local"
environment="${1:-}"

if [[ "${environment}" != "staging" && "${environment}" != "production" ]]; then
  print "Usage: $0 staging|production" >&2
  exit 64
fi
if [[ ! -f "${LOCAL_ENV}" ]]; then
  print "Missing ${LOCAL_ENV}" >&2
  exit 66
fi

set -a
source "${LOCAL_ENV}" >/dev/null 2>&1
set +a

required=(
  AI_TOKEN_SIGNING_SECRET AI_ENROLLMENT_KEYS_FILE AI_APPLE_TOKEN_ENCRYPTION_KEY
  APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID ADMOB_REWARDED_AD_UNIT_ID
  AI_CREDIT_DB_PATH
)
for key in "${required[@]}"; do
  value="${(P)key:-}"
  if [[ -z "${value}" ]]; then
    print "Missing local setting: ${key}" >&2
    exit 65
  fi
done

enrollment_file="${AI_ENROLLMENT_KEYS_FILE/#\~/${HOME}}"
credit_db="${AI_CREDIT_DB_PATH/#\~/${HOME}}"
private_key="${APPLE_PRIVATE_KEY_PATH/#\~/${HOME}}"
if [[ ! -f "${private_key}" ]]; then
  private_key="${HOME}/Library/Application Support/BodyMode/local_ai_server/.sign_in_with_apple/AuthKey_${APPLE_KEY_ID}.p8"
fi
for file in "${enrollment_file}" "${credit_db}" "${private_key}"; do
  [[ -f "${file}" ]] || { print "Missing protected input file: ${file}" >&2; exit 66; }
done

owner_keys="$(sqlite3 "${credit_db}" \
  "SELECT group_concat(account_key, ',') FROM (SELECT DISTINCT account_key FROM ai_credit_lots ORDER BY account_key);")"
[[ -n "${owner_keys}" ]] || { print "No local owner account was found" >&2; exit 65; }

put_secret() {
  local name="$1"
  local value="$2"
  print -rn -- "${value}" | (
    cd "${GATEWAY_DIR}"
    npx wrangler secret put "${name}" --env "${environment}" >/dev/null
  )
  print "configured:${name}"
}

put_secret BODYMODE_TOKEN_SIGNING_SECRET "${AI_TOKEN_SIGNING_SECRET}"
put_secret BODYMODE_ENROLLMENT_KEY_HASHES "$(<"${enrollment_file}")"
put_secret APPLE_REFRESH_TOKEN_ENCRYPTION_KEY "${AI_APPLE_TOKEN_ENCRYPTION_KEY}"
put_secret APPLE_CLIENT_ID "${APPLE_CLIENT_ID}"
put_secret APPLE_TEAM_ID "${APPLE_TEAM_ID}"
put_secret APPLE_KEY_ID "${APPLE_KEY_ID}"
put_secret APPLE_PRIVATE_KEY_P8 "$(<"${private_key}")"
put_secret ADMOB_REWARDED_AD_UNIT_ID "${ADMOB_REWARDED_AD_UNIT_ID}"
put_secret BODYMODE_UNLIMITED_ACCOUNT_KEYS "${owner_keys}"

print "Cloudflare ${environment} secrets configured without printing their values."
