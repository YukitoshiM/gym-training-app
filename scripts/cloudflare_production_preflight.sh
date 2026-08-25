#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_DIR="${ROOT_DIR}/cloudflare_ai_gateway"
BASE_URL="${BODYMODE_PRODUCTION_GATEWAY_URL:-https://bodymode-ai-gateway-production.bodymode-ai.workers.dev}"
OWNER_KEY_FILE="${BODYMODE_OWNER_ENROLLMENT_KEY_FILE:-${HOME}/Library/Application Support/BodyMode/local_ai_server/owner_enrollment_key}"
ALLOW_AI_DEGRADED=0

if [[ "${1:-}" == "--allow-ai-degraded" ]]; then
  ALLOW_AI_DEGRADED=1
elif [[ "$#" -gt 0 ]]; then
  printf 'Usage: %s [--allow-ai-degraded]\n' "$0" >&2
  exit 64
fi

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

json_http_request() {
  local url="$1"
  shift
  local combined body status
  combined="$(curl --silent --show-error --max-time 30 \
    --user-agent 'BodyMode/1.0 production-preflight' \
    --write-out $'\n%{http_code}' "$@" "${url}")" || return 1
  status="${combined##*$'\n'}"
  body="${combined%$'\n'*}"
  printf '%s\n%s' "${status}" "${body}"
}

cd "${GATEWAY_DIR}"

printf '[1/6] Cloudflare authentication and secret inventory\n'
if ! npx wrangler whoami 2>/dev/null | grep -q 'You are logged in'; then
  fail 'Cloudflare CLI is not authenticated'
fi

secret_json="$(npx wrangler secret list --env production)" || fail 'could not read Worker secret names'
secret_audit="$(BODYMODE_PREFLIGHT_JSON="${secret_json}" python3 - "${ALLOW_AI_DEGRADED}" <<'PY'
import json, os, sys

allow_degraded = sys.argv[1] == "1"
configured = {item["name"] for item in json.loads(os.environ["BODYMODE_PREFLIGHT_JSON"])}
required = {
    "ADMOB_REWARDED_AD_UNIT_ID",
    "APPLE_CLIENT_ID",
    "APPLE_KEY_ID",
    "APPLE_PRIVATE_KEY_P8",
    "APPLE_REFRESH_TOKEN_ENCRYPTION_KEY",
    "APPLE_ROOT_CA_BASE64_JSON",
    "APPLE_TEAM_ID",
    "BODYMODE_ENROLLMENT_KEY_HASHES",
    "BODYMODE_TOKEN_SIGNING_SECRET",
    "BODYMODE_UNLIMITED_ACCOUNT_KEYS",
}
if not allow_degraded:
    required.add("OPENAI_API_KEY")
missing = sorted(required - configured)
forbidden = sorted({"BODYMODE_GATEWAY_KEY", "BODYMODE_ORIGIN_URL"} & configured)
if missing:
    print("missing:" + ",".join(missing))
elif forbidden:
    print("forbidden:" + ",".join(forbidden))
else:
    print("ok")
PY
)"
[[ "${secret_audit}" == "ok" ]] || fail "production secret inventory ${secret_audit}"

printf '[2/6] D1 schema, evidence inventory, and pending credits\n'
d1_json="$(npx wrangler d1 execute bodymode-production --env production --remote \
  --command "SELECT (SELECT value FROM schema_metadata WHERE key='schema_version') AS schema_version, (SELECT COUNT(*) FROM evidence_documents) AS documents, (SELECT COUNT(*) FROM evidence_chunks) AS chunks, (SELECT COUNT(*) FROM credit_reservations WHERE status='pending') AS pending_reservations" \
  --json)" || fail 'could not inspect production D1'
d1_summary="$(BODYMODE_PREFLIGHT_JSON="${d1_json}" python3 - <<'PY'
import json, os

payload = json.loads(os.environ["BODYMODE_PREFLIGHT_JSON"])
row = payload[0]["results"][0]
schema = int(row["schema_version"])
documents = int(row["documents"])
chunks = int(row["chunks"])
pending = int(row["pending_reservations"])
if schema < 5:
    raise SystemExit("schema version is below 5")
if documents <= 0 or chunks != documents:
    raise SystemExit("evidence documents and chunks are not aligned")
if pending != 0:
    raise SystemExit("pending credit reservations must be zero before release")
print(f"schema={schema} evidence={documents} pending={pending}")
PY
)" || fail 'production D1 invariant failed'
printf '  %s\n' "${d1_summary}"
evidence_count="${d1_summary#*evidence=}"
evidence_count="${evidence_count%% *}"

printf '[3/6] Vectorize inventory\n'
vector_json="$(npx wrangler vectorize info bodymode-evidence-production --json)" \
  || fail 'could not inspect production Vectorize'
vector_summary="$(BODYMODE_PREFLIGHT_JSON="${vector_json}" python3 - "${evidence_count}" <<'PY'
import json, os, sys

payload = json.loads(os.environ["BODYMODE_PREFLIGHT_JSON"])
expected = int(sys.argv[1])
dimensions = int(payload.get("dimensions", 0))
vectors = int(payload.get("vectorCount", 0))
if dimensions != 1024:
    raise SystemExit("Vectorize dimensions must be 1024")
if vectors != expected:
    raise SystemExit("Vectorize and D1 evidence counts differ")
print(f"dimensions={dimensions} vectors={vectors}")
PY
)" || fail 'production Vectorize invariant failed'
printf '  %s\n' "${vector_summary}"

printf '[4/6] Public health and provider readiness\n'
health_response="$(json_http_request "${BASE_URL}/v1/health")" || fail 'health request failed'
health_status="${health_response%%$'\n'*}"
health_body="${health_response#*$'\n'}"
health_summary="$(BODYMODE_PREFLIGHT_JSON="${health_body}" python3 - "${health_status}" "${ALLOW_AI_DEGRADED}" <<'PY'
import json, os, sys

payload = json.loads(os.environ["BODYMODE_PREFLIGHT_JSON"])
http_status = int(sys.argv[1])
allow_degraded = sys.argv[2] == "1"
required_true = (
    "database_available", "ai_enabled", "apple_sign_in_configured",
    "rewarded_ads_configured", "app_store_verification_configured",
)
if any(payload.get(key) is not True for key in required_true):
    raise SystemExit("one or more production services are not configured")
if int(payload.get("schema_version", 0)) < 5:
    raise SystemExit("health endpoint reports an old schema")
if allow_degraded:
    if http_status not in (200, 503):
        raise SystemExit("unexpected health HTTP status")
else:
    if http_status != 200 or payload.get("status") != "ok" or payload.get("model_available") is not True:
        raise SystemExit("OpenAI provider is not ready")
print(f"http={http_status} status={payload.get('status')} model={payload.get('model')}")
PY
)" || fail 'production health invariant failed'
printf '  %s\n' "${health_summary}"

printf '[5/6] Owner token, unlimited credits, RAG, and operations status\n'
[[ -s "${OWNER_KEY_FILE}" ]] || fail 'owner enrollment key is missing'
owner_key="$(tr -d '\r\n' < "${OWNER_KEY_FILE}")"
auth_response="$(json_http_request "${BASE_URL}/v1/auth/token" \
  --header "Authorization: Bearer ${owner_key}" \
  --header 'Content-Type: application/json' \
  --data '{"installation_id":"bodymode-production-preflight","app_version":"production-preflight"}')" \
  || fail 'owner token request failed'
auth_status="${auth_response%%$'\n'*}"
auth_body="${auth_response#*$'\n'}"
[[ "${auth_status}" == "200" ]] || fail "owner token request returned HTTP ${auth_status}"
access_token="$(printf '%s' "${auth_body}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')" \
  || fail 'owner token response is invalid'

for endpoint in evidence/status credits operations/status; do
  response="$(json_http_request "${BASE_URL}/v1/${endpoint}" \
    --header "Authorization: Bearer ${access_token}")" || fail "${endpoint} request failed"
  status="${response%%$'\n'*}"
  body="${response#*$'\n'}"
  [[ "${status}" == "200" ]] || fail "${endpoint} returned HTTP ${status}"
  BODYMODE_PREFLIGHT_JSON="${body}" python3 - "${endpoint}" "${evidence_count}" <<'PY' \
    || fail "${endpoint} response invariant failed"
import json, os, sys

payload = json.loads(os.environ["BODYMODE_PREFLIGHT_JSON"])
endpoint = sys.argv[1]
evidence_count = int(sys.argv[2])
if endpoint == "evidence/status":
    if payload.get("state") != "ready" or int(payload.get("documents", 0)) != evidence_count:
        raise SystemExit(1)
elif endpoint == "credits":
    if payload.get("unlimited") is not True or payload.get("account_required") is not False:
        raise SystemExit(1)
elif endpoint == "operations/status":
    if int(payload.get("window_hours", 0)) != 24 or "ai" not in payload:
        raise SystemExit(1)
PY
done

printf '[6/6] Public callbacks reject unsigned requests\n'
ssv_status="$(curl --silent --show-error --max-time 30 --output /dev/null --write-out '%{http_code}' \
  --user-agent 'BodyMode/1.0 production-preflight' \
  "${BASE_URL}/v1/credits/rewarded-ad/ssv")" || fail 'rewarded-ad callback request failed'
[[ "${ssv_status}" == "400" ]] || fail "unsigned rewarded-ad callback returned HTTP ${ssv_status}"

printf 'Cloudflare production preflight: PASS\n'
