#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

cd "${ROOT_DIR}"

printf '[1/2] Cloudflare production readiness\n'
if ! ./scripts/cloudflare_production_preflight.sh; then
  failed=1
fi

printf '\n[2/2] Public legal-page synchronization\n'
if ! python3 ./scripts/check_public_legal_pages.py; then
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  printf 'Release prerequisites: FAIL\n' >&2
  exit 1
fi

printf 'Release prerequisites: PASS\n'
