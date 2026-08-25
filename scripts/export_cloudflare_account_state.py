#!/usr/bin/env python3
"""Export encrypted account and credit state from the local backend to D1 SQL."""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import sqlite3
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credit-db", type=Path, required=True)
    parser.add_argument("--apple-token-db", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def sql(value: object) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def main() -> None:
    args = parse_args()
    credit_path = args.credit_db.expanduser().resolve()
    token_path = args.apple_token_db.expanduser().resolve()
    if not credit_path.is_file() or not token_path.is_file():
        raise SystemExit("Both local account databases are required")

    credits = sqlite3.connect(f"file:{credit_path}?mode=ro", uri=True)
    credits.row_factory = sqlite3.Row
    tokens = sqlite3.connect(f"file:{token_path}?mode=ro", uri=True)
    tokens.row_factory = sqlite3.Row
    pending = credits.execute(
        "SELECT COUNT(*) AS count FROM ai_credit_reservations WHERE status = 'pending'"
    ).fetchone()["count"]
    if pending:
        raise SystemExit("Refusing export while AI credit reservations are pending")

    account_keys = {
        str(row["account_key"])
        for row in credits.execute("SELECT DISTINCT account_key FROM ai_credit_lots")
    }
    account_keys.update(
        str(row["account_key"])
        for row in tokens.execute("SELECT DISTINCT account_key FROM apple_refresh_tokens")
    )
    statements = ["PRAGMA foreign_keys = ON;"]
    for account_key in sorted(account_keys):
        created = credits.execute(
            "SELECT MIN(created_at) AS value FROM ai_credit_lots WHERE account_key = ?",
            (account_key,),
        ).fetchone()["value"]
        if created is None:
            created = tokens.execute(
                "SELECT MIN(created_at) AS value FROM apple_refresh_tokens WHERE account_key = ?",
                (account_key,),
            ).fetchone()["value"]
        created = int(created or 0)
        legacy_subject = "legacy:" + hashlib.sha256(account_key.encode("utf-8")).hexdigest()
        statements.append(
            "INSERT OR IGNORE INTO accounts(account_key, apple_subject_hash, created_at) "
            f"VALUES ({sql(account_key)}, {sql(legacy_subject)}, {created});"
        )
        available = credits.execute(
            "SELECT COALESCE(SUM(remaining_amount), 0) AS value "
            "FROM ai_credit_lots WHERE account_key = ?",
            (account_key,),
        ).fetchone()["value"]
        statements.append(
            "INSERT OR IGNORE INTO credit_accounts(account_key, available, reserved, updated_at) "
            f"VALUES ({sql(account_key)}, {int(available)}, 0, {created});"
        )

    for row in credits.execute(
        "SELECT account_key, source, original_amount, remaining_amount, transaction_key, created_at "
        "FROM ai_credit_lots ORDER BY id"
    ):
        statements.append(
            "INSERT OR IGNORE INTO credit_lots("
            "account_key, source, original_amount, remaining_amount, transaction_key, created_at) "
            f"VALUES ({sql(row['account_key'])}, {sql(row['source'])}, "
            f"{int(row['original_amount'])}, {int(row['remaining_amount'])}, "
            f"{sql(row['transaction_key'])}, {int(row['created_at'])});"
        )

    for row in credits.execute(
        "SELECT id, account_key, event_type, amount, source, feature, occurred_at "
        "FROM ai_credit_events ORDER BY id"
    ):
        event_type = str(row["event_type"])
        if event_type not in {"grant", "spend"}:
            continue
        statements.append(
            "INSERT OR IGNORE INTO credit_events("
            "account_key, event_type, amount, source, feature, transaction_key, occurred_at) "
            f"VALUES ({sql(row['account_key'])}, {sql(event_type)}, {abs(int(row['amount']))}, "
            f"{sql(row['source'])}, {sql(row['feature'])}, "
            f"{sql('local_migration:event:' + str(row['id']))}, {int(row['occurred_at'])});"
        )

    for row in tokens.execute(
        "SELECT account_key, token_hash, encrypted_token, created_at "
        "FROM apple_refresh_tokens ORDER BY id"
    ):
        encrypted = bytes(row["encrypted_token"])
        if len(encrypted) <= 28:
            raise SystemExit("Encrypted Apple refresh token is malformed")
        statements.append(
            "INSERT OR IGNORE INTO apple_refresh_tokens("
            "token_id, account_key, encrypted_token, initialization_vector, created_at) "
            f"VALUES ({sql(row['token_hash'])}, {sql(row['account_key'])}, "
            f"{sql(base64url(encrypted[12:]))}, {sql(base64url(encrypted[:12]))}, "
            f"{int(row['created_at'])});"
        )

    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(statements) + "\n", encoding="utf-8")
    os.chmod(output, 0o600)
    print(
        f"accounts={len(account_keys)} "
        f"lots={credits.execute('SELECT COUNT(*) FROM ai_credit_lots').fetchone()[0]} "
        f"tokens={tokens.execute('SELECT COUNT(*) FROM apple_refresh_tokens').fetchone()[0]}"
    )


if __name__ == "__main__":
    main()
