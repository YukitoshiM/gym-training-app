from __future__ import annotations

import os
import re
import sqlite3
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


DAY_SECONDS = 86_400
REASON_CODE_RE = re.compile(r"^[a-z0-9_]{1,40}$")


@dataclass(frozen=True)
class QuotaPolicy:
    feature: str
    limit: int
    window_seconds: int
    calendar_day: bool = False


@dataclass(frozen=True)
class QuotaSnapshot:
    feature: str
    used: int
    limit: int
    remaining: int
    reset_at: int
    window_seconds: int
    duplicate: bool = False

    def as_dict(self) -> dict[str, object]:
        return {
            "feature": self.feature,
            "used": self.used,
            "limit": self.limit,
            "remaining": self.remaining,
            "reset_at": datetime.fromtimestamp(self.reset_at, tz=timezone.utc).isoformat().replace(
                "+00:00", "Z"
            ),
            "window_seconds": self.window_seconds,
        }


class QuotaExceeded(Exception):
    def __init__(self, snapshot: QuotaSnapshot):
        super().__init__(f"Quota exceeded for {snapshot.feature}")
        self.snapshot = snapshot


def _environment_limit(name: str, default: int) -> int:
    return max(1, min(int(os.getenv(name, str(default))), 10_000))


def default_quota_policies() -> tuple[QuotaPolicy, ...]:
    return (
        QuotaPolicy("chat", _environment_limit("AI_QUOTA_CHAT_PER_DAY", 5), DAY_SECONDS, True),
        QuotaPolicy("meal", _environment_limit("AI_QUOTA_MEAL_PER_DAY", 3), DAY_SECONDS, True),
        QuotaPolicy(
            "body_photo",
            _environment_limit("AI_QUOTA_BODY_PHOTO_PER_DAY", 1),
            DAY_SECONDS,
            True,
        ),
        QuotaPolicy(
            "plan_generation",
            _environment_limit("AI_QUOTA_PLAN_PER_DAY", 2),
            DAY_SECONDS,
            True,
        ),
        QuotaPolicy(
            "daily_recommendation",
            _environment_limit("AI_QUOTA_DAILY_RECOMMENDATION_PER_DAY", 1),
            DAY_SECONDS,
            True,
        ),
        QuotaPolicy(
            "weekly_report",
            _environment_limit("AI_QUOTA_WEEKLY_REPORT_PER_7_DAYS", 1),
            7 * DAY_SECONDS,
        ),
        QuotaPolicy(
            "monthly_report",
            _environment_limit("AI_QUOTA_MONTHLY_REPORT_PER_31_DAYS", 1),
            31 * DAY_SECONDS,
        ),
    )


class AIUsageLedger:
    def __init__(
        self,
        path: Path,
        policies: Iterable[QuotaPolicy] | None = None,
        pending_ttl_seconds: int = 900,
    ) -> None:
        self.path = path.expanduser()
        self.policies = {policy.feature: policy for policy in policies or default_quota_policies()}
        self.pending_ttl_seconds = max(60, pending_ttl_seconds)
        self._lock = threading.Lock()
        self._prepare_database()

    def reserve(
        self,
        *,
        client_key: str,
        feature: str,
        request_id: str,
        now: int | None = None,
        enforce_limit: bool = True,
        limit_multiplier: int = 1,
    ) -> QuotaSnapshot:
        policy = self._policy(feature)
        effective_limit = self._effective_limit(policy.limit, limit_multiplier)
        timestamp = int(time.time()) if now is None else int(now)
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                "DELETE FROM ai_usage_ledger WHERE status = 'pending' AND occurred_at < ?",
                (timestamp - self.pending_ttl_seconds,),
            )
            existing = connection.execute(
                "SELECT client_key, feature FROM ai_usage_ledger WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            if existing is not None:
                if existing[0] != client_key or existing[1] != feature:
                    connection.rollback()
                    raise ValueError("Request ID is already assigned to another quota scope")
                snapshot = self._snapshot(
                    connection,
                    client_key,
                    policy,
                    timestamp,
                    duplicate=True,
                    limit_multiplier=limit_multiplier,
                )
                connection.commit()
                return snapshot

            snapshot = self._snapshot(
                connection,
                client_key,
                policy,
                timestamp,
                limit_multiplier=limit_multiplier,
            )
            if enforce_limit and snapshot.remaining <= 0:
                connection.rollback()
                raise QuotaExceeded(snapshot)

            connection.execute(
                """
                INSERT INTO ai_usage_ledger(request_id, client_key, feature, occurred_at, status)
                VALUES (?, ?, ?, ?, 'pending')
                """,
                (request_id, client_key, feature, timestamp),
            )
            connection.commit()
            return QuotaSnapshot(
                feature=feature,
                used=snapshot.used + 1,
                limit=effective_limit,
                remaining=max(0, effective_limit - snapshot.used - 1),
                reset_at=snapshot.reset_at,
                window_seconds=policy.window_seconds,
            )

    def complete(self, request_id: str, duration_ms: int) -> None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT feature, occurred_at FROM ai_usage_ledger WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            connection.execute(
                """
                UPDATE ai_usage_ledger
                SET status = 'success', completed_at = ?, duration_ms = ?
                WHERE request_id = ? AND status = 'pending'
                """,
                (int(time.time()), max(0, int(duration_ms)), request_id),
            )
            if row is not None:
                self._insert_operational_event(connection, str(row[0]), "success", duration_ms, int(row[1]))

    def release(self, request_id: str, outcome: str = "failure", reason_code: str = "unknown") -> None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT feature, occurred_at FROM ai_usage_ledger WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            connection.execute(
                "DELETE FROM ai_usage_ledger WHERE request_id = ? AND status = 'pending'",
                (request_id,),
            )
            if row is not None:
                self._insert_operational_event(
                    connection,
                    str(row[0]),
                    outcome,
                    None,
                    int(row[1]),
                    reason_code=reason_code,
                )

    def record_rejection(self, feature: str, outcome: str) -> None:
        self._policy(feature)
        with self._lock, self._connection() as connection:
            self._insert_operational_event(connection, feature, outcome, None)

    def summary(
        self,
        client_key: str,
        now: int | None = None,
        limit_multipliers: dict[str, int] | None = None,
    ) -> list[QuotaSnapshot]:
        timestamp = int(time.time()) if now is None else int(now)
        multipliers = limit_multipliers or {}
        with self._lock, self._connection() as connection:
            return [
                self._snapshot(
                    connection,
                    client_key,
                    policy,
                    timestamp,
                    limit_multiplier=max(1, int(multipliers.get(policy.feature, 1))),
                )
                for policy in self.policies.values()
            ]

    def operational_summary(self, days: int = 7, now: int | None = None) -> list[dict[str, object]]:
        timestamp = int(time.time()) if now is None else int(now)
        since = timestamp - max(1, days) * DAY_SECONDS
        with self._lock, self._connection() as connection:
            rows = connection.execute(
                """
                SELECT feature, outcome, duration_ms, reason_code
                FROM ai_operational_events
                WHERE occurred_at >= ?
                ORDER BY feature, outcome, duration_ms
                """,
                (since,),
            ).fetchall()
        outcomes_by_feature: dict[str, dict[str, int]] = {}
        failure_reasons_by_feature: dict[str, dict[str, int]] = {}
        durations_by_feature: dict[str, list[int]] = {}
        for feature, outcome, duration_ms, reason_code in rows:
            feature = str(feature)
            outcome = str(outcome)
            outcomes_by_feature.setdefault(feature, {})[outcome] = (
                outcomes_by_feature.setdefault(feature, {}).get(outcome, 0) + 1
            )
            if outcome == "success":
                durations_by_feature.setdefault(feature, []).append(int(duration_ms or 0))
            elif outcome == "failure":
                reason = self._normalized_reason_code(str(reason_code or "unknown"))
                failure_reasons_by_feature.setdefault(feature, {})[reason] = (
                    failure_reasons_by_feature.setdefault(feature, {}).get(reason, 0) + 1
                )
        return [
            {
                "feature": feature,
                "success_count": len(durations),
                "failure_count": outcomes_by_feature.get(feature, {}).get("failure", 0),
                "quota_rejected_count": outcomes_by_feature.get(feature, {}).get("quota_rejected", 0),
                "failure_reasons": dict(sorted(failure_reasons_by_feature.get(feature, {}).items())),
                "average_duration_ms": round(sum(durations) / len(durations)) if durations else 0,
                "p50_duration_ms": self._percentile(durations, 0.50) if durations else 0,
                "p95_duration_ms": self._percentile(durations, 0.95) if durations else 0,
                "maximum_duration_ms": max(durations) if durations else 0,
            }
            for feature in sorted(outcomes_by_feature)
            for durations in [durations_by_feature.get(feature, [])]
        ]

    @staticmethod
    def _insert_operational_event(
        connection: sqlite3.Connection,
        feature: str,
        outcome: str,
        duration_ms: int | None,
        occurred_at: int | None = None,
        reason_code: str | None = None,
    ) -> None:
        normalized_reason = None
        if reason_code is not None:
            candidate = reason_code.strip().lower()
            normalized_reason = candidate if REASON_CODE_RE.fullmatch(candidate) else "unknown"
        connection.execute(
            """
            INSERT INTO ai_operational_events(feature, outcome, occurred_at, duration_ms, reason_code)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                feature,
                outcome,
                int(time.time()) if occurred_at is None else occurred_at,
                None if duration_ms is None else max(0, int(duration_ms)),
                normalized_reason,
            ),
        )

    def _snapshot(
        self,
        connection: sqlite3.Connection,
        client_key: str,
        policy: QuotaPolicy,
        timestamp: int,
        duplicate: bool = False,
        limit_multiplier: int = 1,
    ) -> QuotaSnapshot:
        window_start, default_reset = self._window(policy, timestamp)
        effective_limit = self._effective_limit(policy.limit, limit_multiplier)
        row = connection.execute(
            """
            SELECT COUNT(*), MIN(occurred_at)
            FROM ai_usage_ledger
            WHERE client_key = ? AND feature = ? AND occurred_at >= ?
              AND status IN ('pending', 'success')
            """,
            (client_key, policy.feature, window_start),
        ).fetchone()
        used = int(row[0] or 0)
        earliest = int(row[1]) if row[1] is not None else None
        reset_at = default_reset
        if not policy.calendar_day and earliest is not None:
            reset_at = earliest + policy.window_seconds
        return QuotaSnapshot(
            feature=policy.feature,
            used=used,
            limit=effective_limit,
            remaining=max(0, effective_limit - used),
            reset_at=reset_at,
            window_seconds=policy.window_seconds,
            duplicate=duplicate,
        )

    @staticmethod
    def _effective_limit(policy_limit: int, limit_multiplier: int) -> int:
        multiplier = max(1, int(limit_multiplier))
        return max(1, int(policy_limit * multiplier))

    @staticmethod
    def _window(policy: QuotaPolicy, timestamp: int) -> tuple[int, int]:
        if policy.calendar_day:
            start = timestamp - (timestamp % DAY_SECONDS)
            return start, start + DAY_SECONDS
        return timestamp - policy.window_seconds, timestamp + policy.window_seconds

    @staticmethod
    def _percentile(sorted_values: list[int], fraction: float) -> int:
        index = max(0, min(len(sorted_values) - 1, round((len(sorted_values) - 1) * fraction)))
        return sorted_values[index]

    def _policy(self, feature: str) -> QuotaPolicy:
        try:
            return self.policies[feature]
        except KeyError:
            raise ValueError(f"Unknown AI quota feature: {feature}") from None

    def _prepare_database(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_usage_ledger (
                    request_id TEXT PRIMARY KEY,
                    client_key TEXT NOT NULL,
                    feature TEXT NOT NULL,
                    occurred_at INTEGER NOT NULL,
                    completed_at INTEGER,
                    duration_ms INTEGER,
                    status TEXT NOT NULL CHECK(status IN ('pending', 'success'))
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS ai_operational_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    feature TEXT NOT NULL,
                    outcome TEXT NOT NULL,
                    occurred_at INTEGER NOT NULL,
                    duration_ms INTEGER,
                    reason_code TEXT
                )
                """
            )
            columns = {
                str(row[1])
                for row in connection.execute("PRAGMA table_info(ai_operational_events)").fetchall()
            }
            if "reason_code" not in columns:
                connection.execute("ALTER TABLE ai_operational_events ADD COLUMN reason_code TEXT")
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_ai_operational_time ON ai_operational_events(occurred_at, feature, outcome)"
            )
            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_ai_usage_scope
                ON ai_usage_ledger(client_key, feature, occurred_at, status)
                """
            )
        try:
            os.chmod(self.path, 0o600)
        except OSError:
            pass

    def _connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=5)
        connection.execute("PRAGMA busy_timeout = 5000")
        return connection

    @staticmethod
    def _normalized_reason_code(value: str) -> str:
        normalized = value.strip().lower()
        return normalized if REASON_CODE_RE.fullmatch(normalized) else "unknown"
