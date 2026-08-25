#!/usr/bin/env bash

set -euo pipefail

ENVIRONMENT="${1:-}"
SECURITY_BIN="${BODYMODE_SECURITY_BIN:-security}"
KEYCHAIN_SERVICE="com.bodymode.openai-api-key"

if [[ "${ENVIRONMENT}" != "staging" && "${ENVIRONMENT}" != "production" ]]; then
  printf 'Usage: %s staging|production\n' "$0" >&2
  exit 64
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  printf 'error: run this command directly in an interactive Terminal\n' >&2
  exit 1
fi

KEYCHAIN_ACCOUNT="bodymode-${ENVIRONMENT}"

printf 'This prints the %s OpenAI API key in plain text.\n' "${ENVIRONMENT}" >&2
printf 'Do not share the output or leave it visible in screenshots.\n' >&2
read -r -p 'Type REVEAL to continue: ' confirmation

if [[ "${confirmation}" != "REVEAL" ]]; then
  printf 'Cancelled.\n' >&2
  exit 1
fi

key="$("${SECURITY_BIN}" find-generic-password \
  -a "${KEYCHAIN_ACCOUNT}" \
  -s "${KEYCHAIN_SERVICE}" \
  -w)"
trap 'unset key' EXIT

if [[ -z "${key}" ]]; then
  printf 'error: the Keychain value is empty\n' >&2
  exit 1
fi

printf 'Stored length: %s characters.\n' "${#key}" >&2
printf '%s\n' "${key}"
