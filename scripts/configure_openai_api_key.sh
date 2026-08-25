#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_DIR="${ROOT_DIR}/cloudflare_ai_gateway"
ENVIRONMENT="${1:-}"
SECURITY_BIN="${BODYMODE_SECURITY_BIN:-security}"
NPX_BIN="${BODYMODE_NPX_BIN:-npx}"
SWIFT_BIN="${BODYMODE_SWIFT_BIN:-$(xcrun --find swift)}"
KEYCHAIN_WRITER="${BODYMODE_KEYCHAIN_WRITER:-${ROOT_DIR}/scripts/keychain_secret.swift}"
KEYCHAIN_SERVICE="com.bodymode.openai-api-key"

if [[ "${ENVIRONMENT}" != "staging" && "${ENVIRONMENT}" != "production" ]]; then
  printf 'Usage: %s staging|production\n' "$0" >&2
  exit 64
fi

KEYCHAIN_ACCOUNT="bodymode-${ENVIRONMENT}"
KEYCHAIN_LABEL="BodyMode OpenAI API key (${ENVIRONMENT})"

if ! (
  cd "${GATEWAY_DIR}"
  "${NPX_BIN}" wrangler whoami 2>/dev/null | grep -q 'You are logged in'
); then
  printf 'error: Cloudflare CLI is not authenticated\n' >&2
  exit 1
fi

printf 'Paste the OpenAI key for %s, then press Return.\n' "${ENVIRONMENT}"
printf 'The value is visible while pasting, but is not written to shell history or a file.\n'
IFS= read -r key
trap 'unset key' EXIT

if [[ "${key}" != sk-* || "${#key}" -lt 40 ]]; then
  printf 'error: the entered value does not look like an OpenAI API key\n' >&2
  exit 1
fi

printf '%s' "${key}" | "${SWIFT_BIN}" "${KEYCHAIN_WRITER}" set \
  "${KEYCHAIN_SERVICE}" \
  "${KEYCHAIN_ACCOUNT}" \
  "${KEYCHAIN_LABEL}" \
  "Used only to configure the BodyMode Cloudflare Worker secret"

stored_key="$("${SECURITY_BIN}" find-generic-password \
  -a "${KEYCHAIN_ACCOUNT}" \
  -s "${KEYCHAIN_SERVICE}" \
  -w)"
trap 'unset key stored_key' EXIT

if [[ "${stored_key}" != "${key}" ]]; then
  printf 'error: Keychain verification failed; the stored key differs from the input\n' >&2
  exit 1
fi

printf '%s' "${key}" | (
  cd "${GATEWAY_DIR}"
  "${NPX_BIN}" wrangler secret put OPENAI_API_KEY \
    --env "${ENVIRONMENT}" >/dev/null
)
unset key
unset stored_key

secret_inventory="$(
  cd "${GATEWAY_DIR}"
  "${NPX_BIN}" wrangler secret list --env "${ENVIRONMENT}"
)"
if ! grep -q 'OPENAI_API_KEY' <<<"${secret_inventory}"; then
  printf 'error: Cloudflare did not report the configured secret\n' >&2
  exit 1
fi

printf 'Configured OPENAI_API_KEY for Cloudflare %s.\n' "${ENVIRONMENT}"
printf 'Local copy: macOS Keychain service=%s account=%s\n' \
  "${KEYCHAIN_SERVICE}" "${KEYCHAIN_ACCOUNT}"
printf 'Stored key length verified.\n'
printf 'The key value was not printed.\n'
