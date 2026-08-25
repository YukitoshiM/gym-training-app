from __future__ import annotations

import os
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


ALLOWED_SOURCES = frozenset({"signup", "rewarded_ad", "purchase", "admin"})


def _environment_int(name: str, default: int, minimum: int = 0, maximum: int = 1_000_000) -> int:
    return max(minimum, min(int(os.getenv(name, str(default))), maximum))


def default_feature_costs() -> dict[str, int]:
    return {
        "chat": _environment_int("AI_CREDIT_COST_CHAT", 1, 1),
        "daily_recommendation": _environment_int("AI_CREDIT_COST_DAILY_RECOMMENDATION", 1, 1),
        "plan_generation": _environment_int("AI_CREDIT_COST_PLAN", 2, 1),
        "meal": _environment_int("AI_CREDIT_COST_MEAL", 3, 1),
        "body_photo": _environment_int("AI_CREDIT_COST_BODY_PHOTO", 4, 1),
        "weekly_report": _environment_int("AI_CREDIT_COST_WEEKLY_REPORT", 5, 1),
        "monthly_report": _environment_int("AI_CREDIT_COST_MONTHLY_REPORT", 5, 1),
    }


@dataclass(frozen=True)
class CreditBalance:
    total: int
    available: int
    reserved: int
    buckets: dict[str, int]

    def as_dict(self) -> dict[str, object]:
        return {
            "total": self.total,
            "available": self.available,
            "reserved": self.reserved,
            "buckets": self.buckets,
        }


@dataclass(frozen=True)
class CreditReservation:
    request_id: str
    feature: str
    cost: int
    balance: CreditBalance


class InsufficientCredits(Exception):
    def __init__(self, *, feature: str, cost: int, balance: CreditBalance):
        super().__init__(f"Insufficient credits for {feature}")
        self.feature = feature
        self.cost = cost
        self.balance = balance


class CreditRequestConflict(Exception):
    pass


class AICreditLedger:
    def __init__(
        self,
        path: Path,
        *,
        feature_costs: Mapping[str, int] | None = None,
        signup_bonus: int | None = None,
        pending_ttl_seconds: int = 900,
    ) -> None:
        self.path = path.expanduser()
        self.feature_costs = {
            feature: max(1, int(cost))
            for feature, cost in (feature_costs or default_feature_costs()).items()
        }
        self.signup_bonus = (
            _environment_int("AI_CREDIT_SIGNUP_BONUS", 20)
            if signup_bonus is None
            else max(0, int(signup_bonus))
        )
        self.pending_ttl_seconds = max(60, int(pending_ttl_seconds))
        self._lock = threading.Lock()
        self._prepare_database()

    def claim_signup_bonus(self, account_key: str, now: int | None = None) -> tuple[bool, CreditBalance]:
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            claimed = connection.execute(
                "SELECT 1 FROM ai_credit_signup_claims WHERE account_key = ?",
                (account_key,),
            ).fetchone()
            if claimed is not None or self.signup_bonus == 0:
                balance = self._balance(connection, account_key)
                connection.commit()
                return False, balance
            connection.execute(
                "INSERT INTO ai_credit_signup_claims(account_key, claimed_at) VALUES (?, ?)",
                (account_key, timestamp),
            )
            connection.execute(
                """
                INSERT INTO ai_credit_lots(
                    account_key, source, original_amount, remaining_amount,
                    transaction_key, created_at
                ) VALUES (?, 'signup', ?, ?, ?, ?)
                """,
                (
                    account_key,
                    self.signup_bonus,
                    self.signup_bonus,
                    f"signup:{account_key}",
                    timestamp,
                ),
            )
            self._insert_event(
                connection,
                account_key=account_key,
                event_type="grant",
                amount=self.signup_bonus,
                source="signup",
                feature=None,
                occurred_at=timestamp,
            )
            balance = self._balance(connection, account_key)
            connection.commit()
            return True, balance

    def grant(
        self,
        *,
        account_key: str,
        source: str,
        amount: int,
        transaction_key: str,
        now: int | None = None,
    ) -> bool:
        if source not in ALLOWED_SOURCES:
            raise ValueError("Unsupported credit source")
        normalized_amount = max(0, int(amount))
        if normalized_amount == 0:
            return False
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                "SELECT account_key, source, original_amount FROM ai_credit_lots WHERE transaction_key = ?",
                (transaction_key,),
            ).fetchone()
            if existing is not None:
                if (
                    str(existing[0]) != account_key
                    or str(existing[1]) != source
                    or int(existing[2]) != normalized_amount
                ):
                    connection.rollback()
                    raise CreditRequestConflict("Credit transaction key is already assigned")
                connection.commit()
                return False
            connection.execute(
                """
                INSERT INTO ai_credit_lots(
                    account_key, source, original_amount, remaining_amount,
                    transaction_key, created_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    account_key,
                    source,
                    normalized_amount,
                    normalized_amount,
                    transaction_key,
                    timestamp,
                ),
            )
            self._insert_event(
                connection,
                account_key=account_key,
                event_type="grant",
                amount=normalized_amount,
                source=source,
                feature=None,
                occurred_at=timestamp,
            )
            connection.commit()
            return True

    def grant_purchase(
        self,
        *,
        account_key: str,
        amount: int,
        transaction_key: str,
        now: int | None = None,
    ) -> tuple[bool, int]:
        normalized_amount = max(0, int(amount))
        if normalized_amount == 0:
            return False, 0
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                "SELECT account_key, source, original_amount, remaining_amount FROM ai_credit_lots WHERE transaction_key = ?",
                (transaction_key,),
            ).fetchone()
            if existing is not None:
                if (
                    str(existing[0]) != account_key
                    or str(existing[1]) != "purchase"
                    or int(existing[2]) != normalized_amount
                ):
                    connection.rollback()
                    raise CreditRequestConflict("Credit transaction key is already assigned")
                connection.commit()
                return False, 0

            refund = connection.execute(
                "SELECT status FROM ai_credit_purchase_adjustments WHERE transaction_key = ?",
                (transaction_key,),
            ).fetchone()
            if refund is not None and str(refund[0]) == "refunded":
                connection.execute(
                    """
                    INSERT INTO ai_credit_lots(
                        account_key, source, original_amount, remaining_amount,
                        transaction_key, created_at
                    ) VALUES (?, 'purchase', ?, 0, ?, ?)
                    """,
                    (account_key, normalized_amount, transaction_key, timestamp),
                )
                connection.execute(
                    "UPDATE ai_credit_purchase_adjustments SET account_key = ? WHERE transaction_key = ?",
                    (account_key, transaction_key),
                )
                connection.commit()
                return False, 0

            lot_id = connection.execute(
                """
                INSERT INTO ai_credit_lots(
                    account_key, source, original_amount, remaining_amount,
                    transaction_key, created_at
                ) VALUES (?, 'purchase', ?, ?, ?, ?)
                """,
                (account_key, normalized_amount, normalized_amount, transaction_key, timestamp),
            ).lastrowid
            remaining = normalized_amount
            adjustments = connection.execute(
                """
                SELECT transaction_key, remaining_debt
                FROM ai_credit_purchase_adjustments
                WHERE account_key = ? AND status = 'refunded' AND remaining_debt > 0
                ORDER BY adjusted_at, transaction_key
                """,
                (account_key,),
            ).fetchall()
            for adjustment_key, debt in adjustments:
                applied = min(remaining, int(debt))
                if applied <= 0:
                    continue
                connection.execute(
                    "UPDATE ai_credit_lots SET remaining_amount = remaining_amount - ? WHERE id = ?",
                    (applied, lot_id),
                )
                connection.execute(
                    "UPDATE ai_credit_purchase_adjustments SET remaining_debt = remaining_debt - ? WHERE transaction_key = ?",
                    (applied, str(adjustment_key)),
                )
                self._insert_event(
                    connection,
                    account_key=account_key,
                    event_type="spend",
                    amount=applied,
                    source="purchase",
                    feature="refund_adjustment",
                    occurred_at=timestamp,
                )
                remaining -= applied
                if remaining == 0:
                    break
            if remaining > 0:
                self._insert_event(
                    connection,
                    account_key=account_key,
                    event_type="grant",
                    amount=remaining,
                    source="purchase",
                    feature=None,
                    occurred_at=timestamp,
                )
            connection.commit()
            return True, remaining

    def refund_purchase(
        self,
        *,
        transaction_key: str,
        amount: int,
        now: int | None = None,
    ) -> tuple[bool, str | None, int, int]:
        normalized_amount = max(0, int(amount))
        if normalized_amount == 0:
            return False, None, 0, 0
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing_adjustment = connection.execute(
                "SELECT account_key, removed_amount, remaining_debt FROM ai_credit_purchase_adjustments WHERE transaction_key = ?",
                (transaction_key,),
            ).fetchone()
            if existing_adjustment is not None:
                connection.commit()
                return (
                    False,
                    None if existing_adjustment[0] is None else str(existing_adjustment[0]),
                    int(existing_adjustment[1]),
                    int(existing_adjustment[2]),
                )

            lot = connection.execute(
                "SELECT id, account_key, original_amount, remaining_amount FROM ai_credit_lots WHERE transaction_key = ? AND source = 'purchase'",
                (transaction_key,),
            ).fetchone()
            if lot is None:
                connection.execute(
                    """
                    INSERT INTO ai_credit_purchase_adjustments(
                        transaction_key, account_key, original_amount, removed_amount,
                        remaining_debt, status, adjusted_at
                    ) VALUES (?, NULL, ?, 0, 0, 'refunded', ?)
                    """,
                    (transaction_key, normalized_amount, timestamp),
                )
                connection.commit()
                return True, None, 0, 0

            lot_id, account_key, original_amount, remaining_amount = lot
            if int(original_amount) != normalized_amount:
                connection.rollback()
                raise CreditRequestConflict("Refund amount does not match the purchase")
            removed = min(normalized_amount, int(remaining_amount))
            debt = normalized_amount - removed
            if removed > 0:
                connection.execute(
                    "UPDATE ai_credit_lots SET remaining_amount = remaining_amount - ? WHERE id = ?",
                    (removed, int(lot_id)),
                )
                self._insert_event(
                    connection,
                    account_key=str(account_key),
                    event_type="spend",
                    amount=removed,
                    source="purchase",
                    feature="refund_adjustment",
                    occurred_at=timestamp,
                )
            connection.execute(
                """
                INSERT INTO ai_credit_purchase_adjustments(
                    transaction_key, account_key, original_amount, removed_amount,
                    remaining_debt, status, adjusted_at
                ) VALUES (?, ?, ?, ?, ?, 'refunded', ?)
                """,
                (transaction_key, str(account_key), normalized_amount, removed, debt, timestamp),
            )
            connection.commit()
            return True, str(account_key), removed, debt

    def claim_rewarded_ad(
        self,
        *,
        account_key: str,
        event_id: str,
        amount: int = 5,
        daily_limit: int = 3,
        now: int | None = None,
    ) -> tuple[bool, CreditBalance, int]:
        timestamp = int(time.time()) if now is None else int(now)
        day_start = timestamp - (timestamp % 86_400)
        transaction_key = f"rewarded_ad:{event_id}"
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                "SELECT account_key FROM ai_credit_lots WHERE transaction_key = ?",
                (transaction_key,),
            ).fetchone()
            used = int(connection.execute(
                "SELECT COUNT(*) FROM ai_credit_lots WHERE account_key = ? AND source = 'rewarded_ad' AND created_at >= ?",
                (account_key, day_start),
            ).fetchone()[0])
            if existing is not None:
                if str(existing[0]) != account_key:
                    connection.rollback()
                    raise CreditRequestConflict("Reward event is already assigned")
                balance = self._balance(connection, account_key)
                connection.commit()
                return False, balance, max(0, daily_limit - used)
            if used >= daily_limit:
                balance = self._balance(connection, account_key)
                connection.commit()
                return False, balance, 0

            connection.execute(
                """
                INSERT INTO ai_credit_lots(
                    account_key, source, original_amount, remaining_amount,
                    transaction_key, created_at
                ) VALUES (?, 'rewarded_ad', ?, ?, ?, ?)
                """,
                (account_key, amount, amount, transaction_key, timestamp),
            )
            self._insert_event(
                connection,
                account_key=account_key,
                event_type="grant",
                amount=amount,
                source="rewarded_ad",
                feature=None,
                occurred_at=timestamp,
            )
            balance = self._balance(connection, account_key)
            connection.commit()
            return True, balance, max(0, daily_limit - used - 1)

    def rewarded_ad_remaining(
        self,
        account_key: str,
        daily_limit: int = 3,
        now: int | None = None,
    ) -> int:
        timestamp = int(time.time()) if now is None else int(now)
        day_start = timestamp - (timestamp % 86_400)
        with self._lock, self._connection() as connection:
            used = int(connection.execute(
                "SELECT COUNT(*) FROM ai_credit_lots WHERE account_key = ? AND source = 'rewarded_ad' AND created_at >= ?",
                (account_key, day_start),
            ).fetchone()[0])
        return max(0, int(daily_limit) - used)

    def reserve(
        self,
        *,
        account_key: str,
        feature: str,
        request_id: str,
        now: int | None = None,
    ) -> CreditReservation:
        cost = self.cost_for(feature)
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            self._release_expired_reservations(connection, timestamp)
            existing = connection.execute(
                "SELECT account_key, feature, cost, status FROM ai_credit_reservations WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            if existing is not None:
                connection.rollback()
                raise CreditRequestConflict(
                    "Credit request is already pending" if str(existing[3]) == "pending"
                    else "Credit request is already completed"
                )

            balance = self._balance(connection, account_key)
            if balance.available < cost:
                connection.rollback()
                raise InsufficientCredits(feature=feature, cost=cost, balance=balance)

            connection.execute(
                """
                INSERT INTO ai_credit_reservations(
                    request_id, account_key, feature, cost, status, created_at
                ) VALUES (?, ?, ?, ?, 'pending', ?)
                """,
                (request_id, account_key, feature, cost, timestamp),
            )
            remaining_cost = cost
            lots = connection.execute(
                """
                SELECT id, remaining_amount
                FROM ai_credit_lots
                WHERE account_key = ? AND remaining_amount > 0
                ORDER BY CASE source
                    WHEN 'signup' THEN 0
                    WHEN 'rewarded_ad' THEN 1
                    WHEN 'purchase' THEN 2
                    ELSE 3
                END, created_at, id
                """,
                (account_key,),
            ).fetchall()
            for lot_id, lot_remaining in lots:
                allocated = min(remaining_cost, int(lot_remaining))
                if allocated <= 0:
                    continue
                connection.execute(
                    "UPDATE ai_credit_lots SET remaining_amount = remaining_amount - ? WHERE id = ?",
                    (allocated, int(lot_id)),
                )
                connection.execute(
                    """
                    INSERT INTO ai_credit_reservation_allocations(request_id, lot_id, amount)
                    VALUES (?, ?, ?)
                    """,
                    (request_id, int(lot_id), allocated),
                )
                remaining_cost -= allocated
                if remaining_cost == 0:
                    break
            if remaining_cost != 0:
                connection.rollback()
                raise RuntimeError("Credit allocation did not match available balance")

            updated = self._balance(connection, account_key)
            connection.commit()
            return CreditReservation(request_id, feature, cost, updated)

    def complete(self, request_id: str, now: int | None = None) -> CreditBalance:
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT account_key, feature, cost, status FROM ai_credit_reservations WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            if row is None:
                connection.rollback()
                raise CreditRequestConflict("Unknown credit reservation")
            account_key, feature, cost, status = str(row[0]), str(row[1]), int(row[2]), str(row[3])
            if status == "completed":
                balance = self._balance(connection, account_key)
                connection.commit()
                return balance
            if status != "pending":
                connection.rollback()
                raise CreditRequestConflict("Credit reservation is not pending")
            connection.execute(
                """
                UPDATE ai_credit_reservations
                SET status = 'completed', completed_at = ?
                WHERE request_id = ?
                """,
                (timestamp, request_id),
            )
            self._insert_event(
                connection,
                account_key=account_key,
                event_type="spend",
                amount=-cost,
                source=None,
                feature=feature,
                occurred_at=timestamp,
            )
            balance = self._balance(connection, account_key)
            connection.commit()
            return balance

    def release(self, request_id: str) -> bool:
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            released = self._release_reservation(connection, request_id)
            connection.commit()
            return released

    def balance(self, account_key: str, now: int | None = None) -> CreditBalance:
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            self._release_expired_reservations(connection, timestamp)
            balance = self._balance(connection, account_key)
            connection.commit()
            return balance

    def history(self, account_key: str, limit: int = 100) -> list[dict[str, object]]:
        bounded_limit = max(1, min(int(limit), 500))
        with self._lock, self._connection() as connection:
            rows = connection.execute(
                """
                SELECT id, event_type, amount, source, feature, occurred_at
                FROM ai_credit_events
                WHERE account_key = ?
                ORDER BY id DESC
                LIMIT ?
                """,
                (account_key, bounded_limit),
            ).fetchall()
        return [
            {
                "id": int(row[0]),
                "event_type": str(row[1]),
                "amount": int(row[2]),
                "source": None if row[3] is None else str(row[3]),
                "feature": None if row[4] is None else str(row[4]),
                "occurred_at": int(row[5]),
            }
            for row in rows
        ]

    def delete_account(self, account_key: str) -> dict[str, int]:
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            balance = self._balance(connection, account_key)
            request_ids = [
                str(row[0])
                for row in connection.execute(
                    "SELECT request_id FROM ai_credit_reservations WHERE account_key = ?",
                    (account_key,),
                ).fetchall()
            ]
            for request_id in request_ids:
                connection.execute(
                    "DELETE FROM ai_credit_reservation_allocations WHERE request_id = ?",
                    (request_id,),
                )
            reservations = connection.execute(
                "DELETE FROM ai_credit_reservations WHERE account_key = ?",
                (account_key,),
            ).rowcount
            lots = connection.execute(
                "DELETE FROM ai_credit_lots WHERE account_key = ?",
                (account_key,),
            ).rowcount
            events = connection.execute(
                "DELETE FROM ai_credit_events WHERE account_key = ?",
                (account_key,),
            ).rowcount
            connection.commit()
            return {
                "removed_credits": balance.total,
                "removed_lots": max(0, lots),
                "removed_reservations": max(0, reservations),
                "removed_events": max(0, events),
            }

    def cost_for(self, feature: str) -> int:
        try:
            return self.feature_costs[feature]
        except KeyError:
            raise ValueError(f"Unknown AI credit feature: {feature}") from None

    def _balance(self, connection: sqlite3.Connection, account_key: str) -> CreditBalance:
        rows = connection.execute(
            """
            SELECT source, COALESCE(SUM(remaining_amount), 0)
            FROM ai_credit_lots
            WHERE account_key = ?
            GROUP BY source
            """,
            (account_key,),
        ).fetchall()
        buckets = {source: 0 for source in sorted(ALLOWED_SOURCES)}
        for source, amount in rows:
            buckets[str(source)] = int(amount or 0)
        available = sum(buckets.values())
        reserved_row = connection.execute(
            """
            SELECT COALESCE(SUM(cost), 0)
            FROM ai_credit_reservations
            WHERE account_key = ? AND status = 'pending'
            """,
            (account_key,),
        ).fetchone()
        reserved = int(reserved_row[0] or 0)
        return CreditBalance(
            total=available + reserved,
            available=available,
            reserved=reserved,
            buckets=buckets,
        )

    def _release_expired_reservations(
        self,
        connection: sqlite3.Connection,
        timestamp: int,
    ) -> None:
        request_ids = [
            str(row[0])
            for row in connection.execute(
                """
                SELECT request_id FROM ai_credit_reservations
                WHERE status = 'pending' AND created_at < ?
                """,
                (timestamp - self.pending_ttl_seconds,),
            ).fetchall()
        ]
        for request_id in request_ids:
            self._release_reservation(connection, request_id)

    @staticmethod
    def _release_reservation(connection: sqlite3.Connection, request_id: str) -> bool:
        row = connection.execute(
            "SELECT status FROM ai_credit_reservations WHERE request_id = ?",
            (request_id,),
        ).fetchone()
        if row is None or str(row[0]) != "pending":
            return False
        allocations = connection.execute(
            "SELECT lot_id, amount FROM ai_credit_reservation_allocations WHERE request_id = ?",
            (request_id,),
        ).fetchall()
        for lot_id, amount in allocations:
            connection.execute(
                "UPDATE ai_credit_lots SET remaining_amount = remaining_amount + ? WHERE id = ?",
                (int(amount), int(lot_id)),
            )
        connection.execute(
            "DELETE FROM ai_credit_reservation_allocations WHERE request_id = ?",
            (request_id,),
        )
        connection.execute(
            "DELETE FROM ai_credit_reservations WHERE request_id = ?",
            (request_id,),
        )
        return True

    @staticmethod
    def _insert_event(
        connection: sqlite3.Connection,
        *,
        account_key: str,
        event_type: str,
        amount: int,
        source: str | None,
        feature: str | None,
        occurred_at: int,
    ) -> None:
        connection.execute(
            """
            INSERT INTO ai_credit_events(
                account_key, event_type, amount, source, feature, occurred_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (account_key, event_type, int(amount), source, feature, int(occurred_at)),
        )

    def _prepare_database(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_credit_signup_claims (
                    account_key TEXT PRIMARY KEY,
                    claimed_at INTEGER NOT NULL
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_credit_lots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_key TEXT NOT NULL,
                    source TEXT NOT NULL CHECK(source IN ('signup', 'rewarded_ad', 'purchase', 'admin')),
                    original_amount INTEGER NOT NULL CHECK(original_amount > 0),
                    remaining_amount INTEGER NOT NULL CHECK(remaining_amount >= 0),
                    transaction_key TEXT NOT NULL UNIQUE,
                    created_at INTEGER NOT NULL
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_credit_reservations (
                    request_id TEXT PRIMARY KEY,
                    account_key TEXT NOT NULL,
                    feature TEXT NOT NULL,
                    cost INTEGER NOT NULL CHECK(cost > 0),
                    status TEXT NOT NULL CHECK(status IN ('pending', 'completed')),
                    created_at INTEGER NOT NULL,
                    completed_at INTEGER
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_credit_reservation_allocations (
                    request_id TEXT NOT NULL,
                    lot_id INTEGER NOT NULL,
                    amount INTEGER NOT NULL CHECK(amount > 0),
                    PRIMARY KEY(request_id, lot_id),
                    FOREIGN KEY(request_id) REFERENCES ai_credit_reservations(request_id),
                    FOREIGN KEY(lot_id) REFERENCES ai_credit_lots(id)
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_credit_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_key TEXT NOT NULL,
                    event_type TEXT NOT NULL CHECK(event_type IN ('grant', 'spend')),
                    amount INTEGER NOT NULL,
                    source TEXT,
                    feature TEXT,
                    occurred_at INTEGER NOT NULL
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_credit_purchase_adjustments (
                    transaction_key TEXT PRIMARY KEY,
                    account_key TEXT,
                    original_amount INTEGER NOT NULL CHECK(original_amount > 0),
                    removed_amount INTEGER NOT NULL CHECK(removed_amount >= 0),
                    remaining_debt INTEGER NOT NULL CHECK(remaining_debt >= 0),
                    status TEXT NOT NULL CHECK(status IN ('refunded')),
                    adjusted_at INTEGER NOT NULL
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_credit_lots_account ON ai_credit_lots(account_key, source, created_at)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_credit_reservations_account ON ai_credit_reservations(account_key, status, created_at)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_credit_events_account ON ai_credit_events(account_key, occurred_at)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_credit_adjustments_account ON ai_credit_purchase_adjustments(account_key, status, adjusted_at)"
            )
        try:
            os.chmod(self.path, 0o600)
        except OSError:
            pass

    def _connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=5)
        connection.execute("PRAGMA busy_timeout = 5000")
        connection.execute("PRAGMA foreign_keys = ON")
        return connection
