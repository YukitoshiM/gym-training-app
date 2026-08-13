#!/bin/zsh

set -euo pipefail

SERVER_DIR="${0:A:h}"
PYTHON="${SERVER_DIR}/.venv/bin/python"
ENV_FILE="${SERVER_DIR}/.env.local"

if [[ -r "${ENV_FILE}" ]]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

exec "${PYTHON}" "${SERVER_DIR}/sync_evidence.py" "$@"
