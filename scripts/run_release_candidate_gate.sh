#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STARTED_AT=$(date +%s)
RELEASE_ARTIFACT_PATH="${1:-${BODYMODE_RELEASE_ARTIFACT_PATH:-${BODYMODE_RELEASE_ARCHIVE_PATH:-}}}"

if [[ "$#" -gt 1 ]]; then
  printf 'Usage: %s [archive.xcarchive|exported.ipa]\n' "$0" >&2
  exit 64
fi

cd "${ROOT_DIR}"

if [[ -z "${BODYMODE_REGRESSION_RUN_ID:-}" ]]; then
  BODYMODE_REGRESSION_RUN_ID="release-candidate-$(date '+%Y%m%d-%H%M%S')"
  export BODYMODE_REGRESSION_RUN_ID
fi
REGRESSION_SUMMARY="${ROOT_DIR}/.build/parallel-regression/${BODYMODE_REGRESSION_RUN_ID}/summary.txt"

printf '[1/3] Lightweight production prerequisites\n'
if ! ./scripts/release_prerequisites.sh; then
  printf 'Release candidate gate: BLOCKED before regression\n' >&2
  exit 1
fi

printf '\n[2/3] Full non-screenshot unit, iPhone, and Watch regression gate\n'
set +e
./scripts/run_parallel_simulator_regression.sh
regression_status=$?
set -e
if [[ "${regression_status}" -eq 130 ]]; then
  exit 130
fi

printf '\n[3/3] Production configuration and optional archive preflight\n'
set +e
if [[ -n "${RELEASE_ARTIFACT_PATH}" ]]; then
  BODYMODE_SKIP_RELEASE_PREREQUISITES=1 \
    ./scripts/release_production_preflight.sh "${RELEASE_ARTIFACT_PATH}"
else
  BODYMODE_SKIP_RELEASE_PREREQUISITES=1 \
    ./scripts/release_production_preflight.sh
fi
preflight_status=$?
set -e
if [[ "${preflight_status}" -eq 130 ]]; then
  exit 130
fi

git_sha=$(git rev-parse --short=12 HEAD 2>/dev/null || printf 'unavailable')
if [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]; then
  git_state="dirty"
else
  git_state="clean"
fi
elapsed=$(($(date +%s) - STARTED_AT))
regression_counts="unavailable"
version="unavailable"
if [[ -s "${REGRESSION_SUMMARY}" ]]; then
  regression_counts=$(awk '/^TOTAL / { print; exit }' "${REGRESSION_SUMMARY}")
  version=$(awk -F': ' '/^Version:/ { print $2; exit }' "${REGRESSION_SUMMARY}")
  regression_counts=${regression_counts:-unavailable}
  version=${version:-unavailable}
fi

printf '\nBodyMode release candidate gate summary\n'
printf 'Git SHA: %s\n' "${git_sha}"
printf 'Working tree: %s\n' "${git_state}"
printf 'Version: %s\n' "${version}"
printf 'Regression: %s (status=%s)\n' "${regression_counts}" "${regression_status}"
printf 'Production preflight: status=%s\n' "${preflight_status}"
printf 'Elapsed: %ss\n' "${elapsed}"
printf 'Upload: NOT PERFORMED\n'

if [[ "${regression_status}" -ne 0 || "${preflight_status}" -ne 0 ]]; then
  printf 'Release candidate gate: FAIL\n' >&2
  exit 1
fi

printf 'Release candidate gate: PASS\n'
