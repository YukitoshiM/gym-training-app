#!/bin/zsh

set -euo pipefail

SERVER_DIR="${0:A:h}"
PYTHON="${BODYMODE_PYTHON:-/opt/homebrew/opt/python@3.11/bin/python3.11}"
VENV="${SERVER_DIR}/.venv"

if [[ ! -x "${PYTHON}" ]]; then
  PYTHON="$(command -v python3.11 || true)"
fi
if [[ -z "${PYTHON}" || ! -x "${PYTHON}" ]]; then
  print -u2 "Python 3.11 with SQLite extension loading is required (brew install python@3.11)"
  exit 1
fi

if [[ ! -x "${VENV}/bin/python" ]]; then
  "${PYTHON}" -m venv "${VENV}"
fi

"${VENV}/bin/pip" install -r "${SERVER_DIR}/requirements.txt"
"${VENV}/bin/python" - <<'PY'
import sqlite3
import sqlite_vec

connection = sqlite3.connect(":memory:")
if not hasattr(connection, "enable_load_extension"):
    raise SystemExit("This Python SQLite build cannot load sqlite-vec")
connection.enable_load_extension(True)
sqlite_vec.load(connection)
connection.enable_load_extension(False)
print(
    "Environment ready:",
    f"SQLite {sqlite3.sqlite_version}",
    f"sqlite-vec {connection.execute('SELECT vec_version()').fetchone()[0]}",
)
PY

