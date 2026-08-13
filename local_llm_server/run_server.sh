#!/bin/zsh

set -euo pipefail

SERVER_DIR="${0:A:h}"
PYTHON="${SERVER_DIR}/.venv/bin/python"
KEY_FILE="${SERVER_DIR}/.api_key"
ENV_FILE="${SERVER_DIR}/.env.local"

if [[ ! -x "${PYTHON}" ]]; then
  print -u2 "Missing Python environment: ${PYTHON}"
  exit 1
fi

if [[ ! -r "${KEY_FILE}" ]]; then
  print -u2 "Missing API key file: ${KEY_FILE}"
  exit 1
fi

LOCAL_AI_API_KEY="$(tr -d '\r\n' < "${KEY_FILE}")"
if [[ -z "${LOCAL_AI_API_KEY}" || "${LOCAL_AI_API_KEY}" == "dev-local-key" ]]; then
  print -u2 "Refusing to publish with an empty or development API key"
  exit 1
fi

export LOCAL_AI_API_KEY
export OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
export OLLAMA_MODEL="${OLLAMA_MODEL:-gemma4:12b}"

if [[ -r "${ENV_FILE}" ]]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

export AI_AUTH_STATE_PATH="${AI_AUTH_STATE_PATH:-${HOME}/Library/Application Support/BodyMode/ai-auth-state.json}"
export AI_RATE_LIMIT_PER_MINUTE="${AI_RATE_LIMIT_PER_MINUTE:-30}"
export AI_MAX_CONCURRENT_INFERENCE="${AI_MAX_CONCURRENT_INFERENCE:-2}"

cd "${SERVER_DIR}"
exec "${PYTHON}" -m uvicorn main:app --host 127.0.0.1 --port 8765
