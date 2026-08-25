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
export OLLAMA_REQUEST_TIMEOUT_SECONDS="${OLLAMA_REQUEST_TIMEOUT_SECONDS:-180}"
export OLLAMA_CONTEXT_WINDOW="${OLLAMA_CONTEXT_WINDOW:-4096}"
export OLLAMA_NUM_PREDICT="${OLLAMA_NUM_PREDICT:-512}"
export OLLAMA_MAX_PROMPT_CHARACTERS="${OLLAMA_MAX_PROMPT_CHARACTERS:-3600}"
export OLLAMA_MAX_IMAGE_PROMPT_CHARACTERS="${OLLAMA_MAX_IMAGE_PROMPT_CHARACTERS:-2600}"

if [[ -r "${ENV_FILE}" ]]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

GATEWAY_KEY_FILE="${SERVER_DIR}/.gateway_shared_secret"
if [[ -r "${GATEWAY_KEY_FILE}" ]]; then
  export AI_GATEWAY_SHARED_SECRET="$(tr -d '\r\n' < "${GATEWAY_KEY_FILE}")"
fi

export AI_AUTH_STATE_PATH="${AI_AUTH_STATE_PATH:-${HOME}/Library/Application Support/BodyMode/ai-auth-state.json}"
export AI_USAGE_DB_PATH="${AI_USAGE_DB_PATH:-${HOME}/Library/Application Support/BodyMode/ai-usage.sqlite3}"
export AI_CREDIT_DB_PATH="${AI_CREDIT_DB_PATH:-${HOME}/Library/Application Support/BodyMode/ai-credits.sqlite3}"
export USAGE_ANALYTICS_DB_PATH="${USAGE_ANALYTICS_DB_PATH:-${HOME}/Library/Application Support/BodyMode/usage-analytics.sqlite3}"
export AI_QUOTA_ENFORCEMENT="${AI_QUOTA_ENFORCEMENT:-1}"
export AI_CREDIT_ENFORCEMENT="${AI_CREDIT_ENFORCEMENT:-1}"
export AI_QUOTA_EXEMPT_SUBJECTS="${AI_QUOTA_EXEMPT_SUBJECTS:-}"
export AI_RATE_LIMIT_PER_MINUTE="${AI_RATE_LIMIT_PER_MINUTE:-30}"
export AI_MAX_CONCURRENT_INFERENCE="${AI_MAX_CONCURRENT_INFERENCE:-1}"
export AI_INFERENCE_QUEUE_TIMEOUT_SECONDS="${AI_INFERENCE_QUEUE_TIMEOUT_SECONDS:-8}"

cd "${SERVER_DIR}"
exec "${PYTHON}" -m uvicorn main:app --host 127.0.0.1 --port 8765
