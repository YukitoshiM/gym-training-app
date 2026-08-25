#!/usr/bin/env python3
"""Fetch a compact BodyMode production health and operations report."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


DEFAULT_BASE_URL = "https://bodymode-ai-gateway-production.bodymode-ai.workers.dev"
DEFAULT_OWNER_KEY = (
    Path.home()
    / "Library/Application Support/BodyMode/local_ai_server/owner_enrollment_key"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("BODYMODE_PRODUCTION_GATEWAY_URL", DEFAULT_BASE_URL))
    parser.add_argument("--owner-key-file", type=Path, default=DEFAULT_OWNER_KEY)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--allow-ai-degraded", action="store_true")
    return parser.parse_args()


def request_json(
    url: str,
    *,
    method: str = "GET",
    token: str | None = None,
    enrollment_key: str | None = None,
    payload: dict[str, object] | None = None,
) -> tuple[int, dict[str, object]]:
    headers = {"User-Agent": "BodyMode/1.0 operations-report"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if enrollment_key:
        headers["Authorization"] = f"Bearer {enrollment_key}"
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        try:
            response_payload = json.load(error)
        except (json.JSONDecodeError, UnicodeDecodeError):
            response_payload = {"detail": {"code": "invalid_response", "message": str(error)}}
        return error.code, response_payload


def report_exit_code(report: dict[str, object], allow_ai_degraded: bool = False) -> int:
    health = report.get("health", {})
    operations = report.get("operations", {})
    health_ok = health.get("http_status") == 200 and health.get("status") == "ok"
    if not health_ok and not allow_ai_degraded:
        return 2
    if operations.get("status") == "critical":
        return 2
    if operations.get("status") == "warning" or not health_ok:
        return 1
    return 0


def render_report(report: dict[str, object]) -> str:
    health = report["health"]
    operations = report["operations"]
    ai = operations.get("ai", {})
    credits = operations.get("credits", {})
    notifications = operations.get("app_store_notifications", {})
    success = ai.get("success_rate")
    success_text = "n/a" if success is None else f"{float(success) * 100:.1f}%"
    utilization = ai.get("daily_request_utilization")
    utilization_text = "n/a" if utilization is None else f"{float(utilization) * 100:.1f}%"
    lines = [
        f"BodyMode production: {operations.get('status', 'unknown').upper()}",
        f"Health: HTTP {health.get('http_status')} / {health.get('status')} / {health.get('model')}",
        (
            "AI 24h: "
            f"{ai.get('completed', 0)}/{ai.get('total', 0)} success={success_text} "
            f"p95={ai.get('p95_duration_ms', 0)}ms "
            f"limit={ai.get('total', 0)}/{ai.get('daily_request_limit', 0)} ({utilization_text})"
        ),
        (
            "Credits: "
            f"pending={credits.get('pending_reservations', 0)} "
            f"stale={credits.get('stale_pending_reservations', 0)} "
            f"anomalies={credits.get('invariant_anomalies', 0)}"
        ),
        (
            "App Store notifications: "
            f"processed={notifications.get('processed', 0)} "
            f"rejected={notifications.get('rejected', 0)}"
        ),
    ]
    alerts = operations.get("alerts", [])
    if alerts:
        lines.append("Alerts:")
        lines.extend(
            f"- {item.get('severity', 'warning').upper()} {item.get('code')}: {item.get('message')}"
            for item in alerts
        )
    else:
        lines.append("Alerts: none")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    key_path = args.owner_key_file.expanduser().resolve()
    if not key_path.is_file():
        raise SystemExit(f"Owner enrollment key not found: {key_path}")
    enrollment_key = key_path.read_text(encoding="utf-8").strip()
    base_url = args.base_url.rstrip("/")
    health_status, health = request_json(f"{base_url}/v1/health")
    auth_status, auth = request_json(
        f"{base_url}/v1/auth/token",
        method="POST",
        enrollment_key=enrollment_key,
        payload={"installation_id": "bodymode-operations-report", "app_version": "operations-report"},
    )
    if auth_status != 200 or not auth.get("access_token"):
        raise SystemExit(f"Owner authentication failed with HTTP {auth_status}")
    operations_status, operations = request_json(
        f"{base_url}/v1/operations/status",
        token=str(auth["access_token"]),
    )
    if operations_status != 200:
        raise SystemExit(f"Operations endpoint failed with HTTP {operations_status}")
    report = {
        "health": {"http_status": health_status, **health},
        "operations": operations,
    }
    if args.output:
        output = args.output.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
        os.chmod(output, 0o600)
    print(render_report(report))
    return report_exit_code(report, args.allow_ai_degraded)


if __name__ == "__main__":
    sys.exit(main())
