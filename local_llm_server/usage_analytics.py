from __future__ import annotations

import os
import json
import sqlite3
import threading
import time
import math
from datetime import datetime, timezone
from pathlib import Path


RETENTION_SECONDS = 90 * 86_400


def _wilson_interval(successes: int, total: int, z: float = 1.959963984540054) -> list[float] | None:
    if total <= 0:
        return None
    proportion = successes / total
    denominator = 1 + z * z / total
    center = (proportion + z * z / (2 * total)) / denominator
    margin = z * math.sqrt(
        (proportion * (1 - proportion) + z * z / (4 * total)) / total
    ) / denominator
    return [round(max(0.0, center - margin), 4), round(min(1.0, center + margin), 4)]


class UsageAnalyticsLedger:
    def __init__(self, path: Path) -> None:
        self.path = path.expanduser()
        self._lock = threading.Lock()
        self._prepare_database()

    def record(self, client_key: str, events: list[dict[str, object]]) -> int:
        now = int(time.time())
        rows = [
            (
                str(event["id"]),
                client_key,
                int(event["occurred_at"]),
                str(event["name"]),
                str(event.get("dimension") or "")[:40],
                json.dumps(event.get("properties") or {}, ensure_ascii=True, sort_keys=True),
                str(event.get("app_version") or "")[:40],
                str(event.get("locale") or "")[:20],
                str(event.get("channel") or "app_store")[:20],
            )
            for event in events
        ]
        with self._lock, self._connection() as connection:
            connection.execute("DELETE FROM usage_events WHERE occurred_at < ?", (now - RETENTION_SECONDS,))
            before = connection.total_changes
            connection.executemany(
                """
                INSERT OR IGNORE INTO usage_events(
                    event_id, client_key, occurred_at, name, dimension, properties_json, app_version, locale, channel
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                rows,
            )
            return connection.total_changes - before

    def summary(self, days: int = 30, now: int | None = None) -> dict[str, object]:
        timestamp = int(time.time()) if now is None else int(now)
        since = timestamp - max(1, min(days, 90)) * 86_400
        with self._lock, self._connection() as connection:
            event_rows = connection.execute(
                """
                SELECT name, COUNT(*) FROM usage_events
                WHERE occurred_at >= ? GROUP BY name ORDER BY name
                """,
                (since,),
            ).fetchall()
            active_users = int(connection.execute(
                "SELECT COUNT(DISTINCT client_key) FROM usage_events WHERE occurred_at >= ?",
                (since,),
            ).fetchone()[0] or 0)
            active_days = int(connection.execute(
                "SELECT COUNT(DISTINCT client_key || ':' || date(occurred_at, 'unixepoch')) FROM usage_events WHERE occurred_at >= ?",
                (since,),
            ).fetchone()[0] or 0)
            by_channel_rows = connection.execute(
                """
                SELECT
                    channel,
                    COUNT(DISTINCT client_key),
                    COUNT(DISTINCT client_key || ':' || date(occurred_at, 'unixepoch'))
                FROM usage_events
                WHERE occurred_at >= ?
                GROUP BY channel
                ORDER BY channel
                """,
                (since,),
            ).fetchall()
            by_channel = {
                str(row[0]): {
                    "active_users": int(row[1]),
                    "active_user_days": int(row[2]),
                }
                for row in by_channel_rows
            }
            completed_days = int(connection.execute(
                """
                SELECT COUNT(DISTINCT client_key || ':' || date(occurred_at, 'unixepoch'))
                FROM usage_events
                WHERE occurred_at >= ? AND name = 'daily_action_completed'
                """,
                (since,),
            ).fetchone()[0] or 0)
            milestone_users = {
                name: int(connection.execute(
                    "SELECT COUNT(DISTINCT client_key) FROM usage_events WHERE occurred_at >= ? AND name = ?",
                    (since, name),
                ).fetchone()[0] or 0)
                for name in (
                    "initial_setup_completed",
                    "first_workout_completed",
                    "daily_action_completed",
                )
            }
            retention = {
                f"d{day}": self._retention(connection, day, timestamp)
                for day in (1, 7, 30)
            }
            daily_action_rows = connection.execute(
                """
                SELECT name,
                       json_extract(properties_json, '$.goal') AS goal,
                       json_extract(properties_json, '$.experience') AS experience,
                       json_extract(properties_json, '$.readiness') AS readiness,
                       json_extract(properties_json, '$.actionCategory') AS action_category,
                       json_extract(properties_json, '$.fromCategory') AS from_category,
                       json_extract(properties_json, '$.toCategory') AS to_category,
                       json_extract(properties_json, '$.position') AS position,
                       json_extract(properties_json, '$.source') AS source,
                       json_extract(properties_json, '$.reason') AS reason,
                       json_extract(properties_json, '$.completionMethod') AS completion_method,
                       COUNT(*) AS event_count,
                       COUNT(DISTINCT client_key) AS users,
                       COUNT(DISTINCT client_key || ':' || date(occurred_at, 'unixepoch')) AS user_days
                FROM usage_events
                WHERE occurred_at >= ? AND name IN (
                    'daily_action_impression', 'home_primary_action_started',
                    'daily_action_completed', 'daily_action_replaced', 'daily_action_dismissed'
                )
                GROUP BY name, goal, experience, readiness, action_category, from_category,
                         to_category, position,
                         source, reason, completion_method
                ORDER BY name, event_count DESC
                """,
                (since,),
            ).fetchall()
            daily_action_funnel_rows = connection.execute(
                """
                WITH classified AS (
                    SELECT client_key,
                           date(occurred_at, 'unixepoch') AS event_day,
                           name,
                           json_extract(properties_json, '$.goal') AS goal,
                           json_extract(properties_json, '$.experience') AS experience,
                           CASE
                               WHEN name = 'daily_action_replaced'
                               THEN json_extract(properties_json, '$.fromCategory')
                               ELSE json_extract(properties_json, '$.actionCategory')
                           END AS action_category
                    FROM usage_events
                    WHERE occurred_at >= ? AND name IN (
                        'daily_action_impression', 'home_primary_action_started',
                        'daily_action_completed', 'daily_action_replaced', 'daily_action_dismissed'
                    )
                )
                SELECT goal, experience, action_category,
                       COUNT(DISTINCT CASE WHEN name = 'daily_action_impression'
                           THEN client_key || ':' || event_day END) AS impression_user_days,
                       COUNT(DISTINCT CASE WHEN name = 'home_primary_action_started'
                           THEN client_key || ':' || event_day END) AS started_user_days,
                       COUNT(DISTINCT CASE WHEN name = 'daily_action_completed'
                           THEN client_key || ':' || event_day END) AS completed_user_days,
                       COUNT(DISTINCT CASE WHEN name = 'daily_action_replaced'
                           THEN client_key || ':' || event_day END) AS replaced_user_days,
                       COUNT(DISTINCT CASE WHEN name = 'daily_action_dismissed'
                           THEN client_key || ':' || event_day END) AS dismissed_user_days
                FROM classified
                WHERE goal IS NOT NULL AND experience IS NOT NULL AND action_category IS NOT NULL
                GROUP BY goal, experience, action_category
                ORDER BY impression_user_days DESC, goal, experience, action_category
                """,
                (since,),
            ).fetchall()
            monetization_event_names = (
                "ai_account_registered",
                "ai_signup_grant_received",
                "ai_credit_insufficient_shown",
                "credit_store_opened",
                "rewarded_ad_started",
                "rewarded_ad_completed",
                "rewarded_ad_failed",
                "rewarded_credit_granted",
                "credit_purchase_completed",
                "credit_purchase_pending",
                "credit_purchase_cancelled",
                "credit_purchase_failed",
            )
            monetization_rows = connection.execute(
                f"""
                SELECT name, '__all__' AS channel, COUNT(*), COUNT(DISTINCT client_key)
                FROM usage_events
                WHERE occurred_at >= ?
                  AND name IN ({','.join('?' for _ in monetization_event_names)})
                GROUP BY name
                UNION ALL
                SELECT name, channel, COUNT(*), COUNT(DISTINCT client_key)
                FROM usage_events
                WHERE occurred_at >= ?
                  AND name IN ({','.join('?' for _ in monetization_event_names)})
                GROUP BY name, channel
                ORDER BY name, channel
                """,
                (since, *monetization_event_names, since, *monetization_event_names),
            ).fetchall()
        counts = {str(name): int(count) for name, count in event_rows}
        return {
            "generated_at": datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "days": max(1, min(days, 90)),
            "active_users": active_users,
            "active_user_days": active_days,
            "north_star_completed_user_days": completed_days,
            "north_star_rate": round(completed_days / active_days, 4) if active_days else 0,
            "by_channel": by_channel,
            "event_counts": counts,
            "milestones": {
                name: {
                    "users": users,
                    "active_user_rate": round(users / active_users, 4) if active_users else 0,
                }
                for name, users in milestone_users.items()
            },
            "retention": retention,
            "daily_action_research": [
                {
                    "event": row[0],
                    "goal": row[1],
                    "experience": row[2],
                    "readiness": row[3],
                    "action_category": row[4],
                    "from_category": row[5],
                    "to_category": row[6],
                    "position": row[7],
                    "source": row[8],
                    "reason": row[9],
                    "completion_method": row[10],
                    "event_count": int(row[11]),
                    "users": int(row[12]),
                    "user_days": int(row[13]),
                }
                for row in daily_action_rows
            ],
            "daily_action_funnel": [
                self._funnel_row(row)
                for row in daily_action_funnel_rows
            ],
            "monetization_funnel": self._monetization_funnel(monetization_rows),
        }

    @staticmethod
    def _monetization_funnel(rows: list[tuple[object, ...]]) -> dict[str, object]:
        events: dict[str, dict[str, object]] = {}
        for name, channel, count, users in rows:
            event = events.setdefault(str(name), {"events": 0, "users": 0, "by_channel": {}})
            if channel == "__all__":
                event["events"] = int(count)
                event["users"] = int(users)
            else:
                event["by_channel"][str(channel)] = {
                    "events": int(count),
                    "users": int(users),
                }
        return {"events": events}

    @staticmethod
    def _funnel_row(row: tuple[object, ...]) -> dict[str, object]:
        impressions = int(row[3])
        starts = int(row[4])
        completions = int(row[5])
        replacements = int(row[6])
        dismissals = int(row[7])

        def metric(value: int) -> dict[str, object]:
            valid = impressions > 0 and value <= impressions
            return {
                "user_days": value,
                "rate": round(value / impressions, 4) if impressions else None,
                "ci95": _wilson_interval(value, impressions) if valid else None,
            }

        return {
            "goal": row[0],
            "experience": row[1],
            "action_category": row[2],
            "impression_user_days": impressions,
            "started": metric(starts),
            "completed": metric(completions),
            "replaced": metric(replacements),
            "dismissed": metric(dismissals),
            "denominator_valid": impressions > 0 and all(
                value <= impressions for value in (starts, completions, replacements, dismissals)
            ),
        }

    def delete(self, client_key: str) -> int:
        with self._lock, self._connection() as connection:
            before = connection.total_changes
            connection.execute("DELETE FROM usage_events WHERE client_key = ?", (client_key,))
            return connection.total_changes - before

    @staticmethod
    def _retention(connection: sqlite3.Connection, day: int, now: int) -> dict[str, object]:
        eligible_before = now - day * 86_400
        rows = connection.execute(
            """
            WITH installs AS (
                SELECT client_key, MIN(occurred_at) AS first_at
                FROM usage_events GROUP BY client_key
            )
            SELECT i.client_key, i.first_at,
                   EXISTS(
                       SELECT 1 FROM usage_events e
                       WHERE e.client_key = i.client_key
                         AND e.occurred_at >= i.first_at + ?
                         AND e.occurred_at < i.first_at + ?
                   )
            FROM installs i WHERE i.first_at <= ?
            """,
            (day * 86_400, (day + 1) * 86_400, eligible_before),
        ).fetchall()
        retained = sum(1 for _, _, present in rows if present)
        return {
            "eligible": len(rows),
            "retained": retained,
            "rate": round(retained / len(rows), 4) if rows else 0,
        }

    def _prepare_database(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_events (
                    event_id TEXT PRIMARY KEY,
                    client_key TEXT NOT NULL,
                    occurred_at INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    dimension TEXT NOT NULL,
                    properties_json TEXT NOT NULL DEFAULT '{}',
                    app_version TEXT NOT NULL,
                    locale TEXT NOT NULL,
                    channel TEXT NOT NULL DEFAULT 'unknown'
                )
                """
            )
            columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(usage_events)").fetchall()
            }
            if "properties_json" not in columns:
                connection.execute(
                    "ALTER TABLE usage_events ADD COLUMN properties_json TEXT NOT NULL DEFAULT '{}'"
                )
            if "channel" not in columns:
                connection.execute(
                    "ALTER TABLE usage_events ADD COLUMN channel TEXT NOT NULL DEFAULT 'unknown'"
                )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_usage_events_time ON usage_events(occurred_at, name)"
            )
        try:
            os.chmod(self.path, 0o600)
        except OSError:
            pass

    def _connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=5)
        connection.execute("PRAGMA busy_timeout = 5000")
        return connection
