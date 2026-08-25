#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/docs/research-prototypes/bodymode_core_research_runner.html"
PORT="${BODYMODE_RESEARCH_PORT:-8793}"

if [[ ! -r "${SOURCE}" ]]; then
  echo "error: research runner not found" >&2
  exit 1
fi

for command in python3 cloudflared; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: ${command} is required" >&2
    exit 1
  fi
done

serve_dir="$(mktemp -d /tmp/bodymode-research-site.XXXXXX)"
server_pid=""

cleanup() {
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -f "${serve_dir}/index.html"
  rmdir "${serve_dir}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cp "${SOURCE}" "${serve_dir}/index.html"
python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${serve_dir}" >/dev/null 2>&1 &
server_pid="$!"

echo "Research responses remain in each participant's browser until they export JSON."
echo "Starting temporary public URL. Stop with Ctrl-C."
cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${PORT}"
