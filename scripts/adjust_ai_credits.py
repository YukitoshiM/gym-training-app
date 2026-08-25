#!/usr/bin/env python3
"""Grant an audited, idempotent BodyMode support credit adjustment."""

from __future__ import annotations

import argparse
import json
import uuid
from pathlib import Path

from cloudflare_operations_report import DEFAULT_BASE_URL, DEFAULT_OWNER_KEY, request_json


REASONS = ("purchase_missing", "reward_missing", "service_recovery", "other")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--support-id", required=True)
    parser.add_argument("--amount", required=True, type=int)
    parser.add_argument("--reason", required=True, choices=REASONS)
    parser.add_argument("--adjustment-id", default=str(uuid.uuid4()))
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--owner-key-file", type=Path, default=DEFAULT_OWNER_KEY)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Send the adjustment. Without this flag, only the validated request is shown.",
    )
    parser.add_argument(
        "--confirm-support-id",
        help="Required with --apply and must exactly match --support-id.",
    )
    return parser.parse_args()


def normalized_payload(args: argparse.Namespace) -> dict[str, object]:
    support_id = str(args.support_id).strip().lower()
    adjustment_id = str(args.adjustment_id).strip().lower()
    if len(support_id) != 16 or any(character not in "0123456789abcdef" for character in support_id):
        raise ValueError("support ID must be 16 hexadecimal characters")
    try:
        adjustment_id = str(uuid.UUID(adjustment_id))
    except ValueError as error:
        raise ValueError("adjustment ID must be a UUID") from error
    if not 1 <= int(args.amount) <= 500:
        raise ValueError("amount must be between 1 and 500")
    return {
        "support_id": support_id,
        "adjustment_id": adjustment_id,
        "amount": int(args.amount),
        "reason": str(args.reason),
    }


def main() -> int:
    args = parse_args()
    try:
        payload = normalized_payload(args)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    if not args.apply:
        print("DRY RUN: add --apply --confirm-support-id " + str(payload["support_id"]))
        print(json.dumps(payload, ensure_ascii=True, indent=2))
        return 0
    if str(args.confirm_support_id or "").strip().lower() != payload["support_id"]:
        raise SystemExit("--confirm-support-id must match --support-id")

    key_path = args.owner_key_file.expanduser().resolve()
    if not key_path.is_file():
        raise SystemExit(f"Owner enrollment key not found: {key_path}")
    enrollment_key = key_path.read_text(encoding="utf-8").strip()
    base_url = str(args.base_url).rstrip("/")
    auth_status, auth = request_json(
        f"{base_url}/v1/auth/token",
        method="POST",
        enrollment_key=enrollment_key,
        payload={"installation_id": "bodymode-support-cli", "app_version": "support-cli"},
    )
    if auth_status != 200 or not auth.get("access_token"):
        raise SystemExit(f"Owner authentication failed with HTTP {auth_status}")
    status, response = request_json(
        f"{base_url}/v1/operations/credits/grant",
        method="POST",
        token=str(auth["access_token"]),
        payload=payload,
    )
    if status != 200:
        detail = response.get("detail", {})
        raise SystemExit(f"Adjustment failed with HTTP {status}: {detail.get('code', 'unknown_error')}")
    print(json.dumps(response, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
