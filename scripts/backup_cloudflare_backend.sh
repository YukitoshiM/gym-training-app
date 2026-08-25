#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_DIR="${ROOT_DIR}/cloudflare_ai_gateway"
BACKUP_ROOT="${BODYMODE_CLOUDFLARE_BACKUP_ROOT:-${HOME}/Library/Application Support/BodyMode/backups/cloudflare}"
ENVIRONMENT="production"
WITH_EVIDENCE=0
RETENTION_DAYS=14

usage() {
  printf 'Usage: %s [--env production|staging] [--output directory] [--with-evidence] [--retention-days N]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --output) BACKUP_ROOT="$2"; shift 2 ;;
    --with-evidence) WITH_EVIDENCE=1; shift ;;
    --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done

[[ "${ENVIRONMENT}" == "production" || "${ENVIRONMENT}" == "staging" ]] || {
  printf 'error: --env must be production or staging\n' >&2
  exit 64
}
[[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]] || {
  printf 'error: --retention-days must be a non-negative integer\n' >&2
  exit 64
}

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
WRANGLER=(npx --yes wrangler@4.123.0)
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT%/}/${ENVIRONMENT}/${timestamp}"
database="bodymode-${ENVIRONMENT}"
worker="bodymode-ai-gateway-${ENVIRONMENT}"
vector="bodymode-evidence-${ENVIRONMENT}"

umask 077
mkdir -p "${backup_dir}"
cd "${GATEWAY_DIR}"

"${WRANGLER[@]}" whoami >/dev/null
"${WRANGLER[@]}" d1 export "${database}" --env "${ENVIRONMENT}" --remote \
  --skip-confirmation --output "${backup_dir}/d1.sql"
"${WRANGLER[@]}" deployments list --env "${ENVIRONMENT}" --name "${worker}" --json \
  > "${backup_dir}/deployments.json"
"${WRANGLER[@]}" secret list --env "${ENVIRONMENT}" > "${backup_dir}/secret-names.json"
"${WRANGLER[@]}" vectorize info "${vector}" --json > "${backup_dir}/vectorize.json"
install -m 600 wrangler.jsonc "${backup_dir}/wrangler.jsonc"

if [[ "${WITH_EVIDENCE}" == "1" ]]; then
  evidence_db="${BODYMODE_EVIDENCE_DB:-${HOME}/Library/Application Support/BodyMode/evidence-rag.sqlite3}"
  python_bin="${ROOT_DIR}/local_llm_server/.venv/bin/python"
  [[ -f "${evidence_db}" ]] || { printf 'error: evidence DB not found: %s\n' "${evidence_db}" >&2; exit 1; }
  [[ -x "${python_bin}" ]] || { printf 'error: evidence Python runtime not found\n' >&2; exit 1; }
  "${python_bin}" "${ROOT_DIR}/scripts/export_cloudflare_evidence.py" \
    --db "${evidence_db}" --output "${backup_dir}/evidence"
fi

(
  cd "${backup_dir}"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS
)

if [[ "${RETENTION_DAYS}" -gt 0 ]]; then
  find "${BACKUP_ROOT%/}/${ENVIRONMENT}" -mindepth 1 -maxdepth 1 -type d \
    -mtime "+${RETENTION_DAYS}" -exec rm -rf {} +
fi

printf 'Cloudflare backup complete: %s\n' "${backup_dir}"
