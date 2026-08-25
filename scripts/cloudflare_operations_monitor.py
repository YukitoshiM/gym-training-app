#!/usr/bin/env python3
"""Run the BodyMode operations report and notify on state changes."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path


DEFAULT_OPERATIONS_DIR = Path.home() / "Library/Application Support/BodyMode/operations"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--report-script",
        type=Path,
        default=Path(__file__).with_name("cloudflare_operations_report.py"),
    )
    parser.add_argument("--report-output", type=Path, default=DEFAULT_OPERATIONS_DIR / "latest.json")
    parser.add_argument("--state-file", type=Path, default=DEFAULT_OPERATIONS_DIR / "monitor-state.json")
    parser.add_argument("--renotify-seconds", type=int, default=21_600)
    parser.add_argument("--no-notification", action="store_true")
    return parser.parse_args()


def level_for_exit_code(code: int) -> str:
    if code == 0:
        return "ok"
    if code == 1:
        return "warning"
    return "critical"


def notification_needed(previous: dict[str, object], level: str, now: int, interval: int) -> bool:
    prior_level = str(previous.get("level") or "unknown")
    last_notified = int(previous.get("last_notified_at") or 0)
    if prior_level != level:
        return True
    return level != "ok" and now - last_notified >= max(300, interval)


def read_state(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def write_state(path: Path, state: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    os.chmod(path, 0o600)


def notify(level: str) -> None:
    messages = {
        "ok": "BodyMode production has recovered.",
        "warning": "BodyMode production requires attention. Check the operations report.",
        "critical": "BodyMode production has a critical alert. Check it now.",
    }
    subprocess.run(
        [
            "/usr/bin/osascript",
            "-e",
            f'display notification "{messages[level]}" with title "BodyMode Operations"',
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def main() -> int:
    args = parse_args()
    report_script = args.report_script.expanduser().resolve()
    report_output = args.report_output.expanduser().resolve()
    state_file = args.state_file.expanduser().resolve()
    result = subprocess.run(
        [sys.executable, str(report_script), "--output", str(report_output)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)

    now = int(time.time())
    level = level_for_exit_code(result.returncode)
    previous = read_state(state_file)
    should_notify = notification_needed(previous, level, now, args.renotify_seconds)
    did_notify = should_notify and not args.no_notification
    if did_notify:
        notify(level)
    write_state(state_file, {
        "level": level,
        "checked_at": now,
        "last_notified_at": now if did_notify else int(previous.get("last_notified_at") or 0),
        "report_exit_code": result.returncode,
    })
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
