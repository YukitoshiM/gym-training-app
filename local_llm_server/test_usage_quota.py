import tempfile
import unittest
import sqlite3
from pathlib import Path

from usage_quota import AIUsageLedger, QuotaExceeded, QuotaPolicy


class AIUsageLedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database_path = Path(self.temporary_directory.name) / "usage.sqlite3"
        self.policies = (
            QuotaPolicy("chat", limit=2, window_seconds=86_400, calendar_day=True),
            QuotaPolicy("weekly_report", limit=1, window_seconds=7 * 86_400),
        )
        self.ledger = AIUsageLedger(self.database_path, self.policies)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_successful_usage_persists_across_server_restart(self) -> None:
        reserved = self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id="request-1",
            now=1_700_000_000,
        )
        self.assertEqual(reserved.remaining, 1)
        self.ledger.complete("request-1", 1_250)

        restarted = AIUsageLedger(self.database_path, self.policies)
        snapshot = restarted.summary("anonymous-client", now=1_700_000_001)[0]

        self.assertEqual(snapshot.used, 1)
        self.assertEqual(snapshot.remaining, 1)

    def test_failed_usage_is_released_without_consuming_quota(self) -> None:
        self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id="request-failed",
            now=1_700_000_000,
        )
        self.ledger.release("request-failed")

        snapshot = self.ledger.summary("anonymous-client", now=1_700_000_001)[0]

        self.assertEqual(snapshot.used, 0)
        self.assertEqual(snapshot.remaining, 2)

    def test_same_request_id_is_not_counted_twice(self) -> None:
        first = self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id="request-same",
            now=1_700_000_000,
        )
        duplicate = self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id="request-same",
            now=1_700_000_001,
        )

        self.assertFalse(first.duplicate)
        self.assertTrue(duplicate.duplicate)
        self.assertEqual(duplicate.used, 1)

    def test_limit_returns_reset_information(self) -> None:
        for index in range(2):
            request_id = f"request-{index}"
            self.ledger.reserve(
                client_key="anonymous-client",
                feature="chat",
                request_id=request_id,
                now=1_700_000_000 + index,
            )
            self.ledger.complete(request_id, 500)

        with self.assertRaises(QuotaExceeded) as captured:
            self.ledger.reserve(
                client_key="anonymous-client",
                feature="chat",
                request_id="request-over",
                now=1_700_000_010,
            )

        self.assertEqual(captured.exception.snapshot.remaining, 0)
        self.assertGreater(captured.exception.snapshot.reset_at, 1_700_000_010)

    def test_unenforced_mode_records_usage_beyond_limit(self) -> None:
        for index in range(3):
            request_id = f"testflight-{index}"
            snapshot = self.ledger.reserve(
                client_key="testflight-client",
                feature="chat",
                request_id=request_id,
                now=1_700_000_000 + index,
                enforce_limit=False,
            )
            self.ledger.complete(request_id, 500)

        self.assertEqual(snapshot.used, 3)
        self.assertEqual(snapshot.remaining, 0)
        self.assertEqual(
            self.ledger.summary("testflight-client", now=1_700_000_010)[0].used,
            3,
        )

    def test_reserve_supports_limit_multiplier(self) -> None:
        snapshots = []
        for index in range(4):
            request_id = f"multiplier-{index}"
            snapshots.append(
                self.ledger.reserve(
                    client_key="anonymous-client",
                    feature="chat",
                    request_id=request_id,
                    now=1_700_000_000 + index,
                    limit_multiplier=2,
                )
            )
            self.ledger.complete(request_id, 120)

        self.assertEqual(snapshots[-1].used, 4)
        self.assertEqual(snapshots[-1].limit, 4)
        self.assertEqual(snapshots[-1].remaining, 0)
        self.assertEqual(self.ledger.summary("anonymous-client", now=1_700_000_010)[0].used, 4)

    def test_summary_accepts_limit_multipliers(self) -> None:
        request_id = "test-summary-multiplier"
        self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id=request_id,
            now=1_700_000_000,
            limit_multiplier=2,
        )
        self.ledger.complete(request_id, 120)

        summary = self.ledger.summary(
            "anonymous-client",
            now=1_700_000_001,
            limit_multipliers={"chat": 2},
        )[0]

        self.assertEqual(summary.used, 1)
        self.assertEqual(summary.limit, 4)
        self.assertEqual(summary.remaining, 3)

    def test_operational_summary_contains_only_aggregate_metrics(self) -> None:
        self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id="request-summary",
            now=1_700_000_000,
        )
        self.ledger.complete("request-summary", 900)

        summary = self.ledger.operational_summary(days=7, now=1_700_000_100)

        self.assertEqual(summary[0]["feature"], "chat")
        self.assertEqual(summary[0]["success_count"], 1)
        self.assertEqual(summary[0]["p50_duration_ms"], 900)
        self.assertEqual(summary[0]["p95_duration_ms"], 900)
        self.assertNotIn("client_key", summary[0])
        self.assertNotIn("request_id", summary[0])

    def test_operational_summary_groups_sanitized_failure_reasons(self) -> None:
        self.ledger.reserve(
            client_key="anonymous-client",
            feature="chat",
            request_id="request-failure-reason",
            now=1_700_000_000,
        )
        self.ledger.release("request-failure-reason", reason_code="model_unavailable")

        summary = self.ledger.operational_summary(days=7, now=1_700_000_100)

        self.assertEqual(summary[0]["failure_count"], 1)
        self.assertEqual(summary[0]["failure_reasons"], {"model_unavailable": 1})
        self.assertNotIn("anonymous-client", str(summary[0]))

    def test_existing_operational_table_is_migrated_without_data_loss(self) -> None:
        legacy_path = Path(self.temporary_directory.name) / "legacy.sqlite3"
        with sqlite3.connect(legacy_path) as connection:
            connection.execute(
                """
                CREATE TABLE ai_operational_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    feature TEXT NOT NULL,
                    outcome TEXT NOT NULL,
                    occurred_at INTEGER NOT NULL,
                    duration_ms INTEGER
                )
                """
            )
            connection.execute(
                "INSERT INTO ai_operational_events(feature, outcome, occurred_at, duration_ms) VALUES ('chat', 'failure', 1700000000, NULL)"
            )

        migrated = AIUsageLedger(legacy_path, self.policies)
        summary = migrated.operational_summary(days=7, now=1_700_000_100)

        self.assertEqual(summary[0]["failure_reasons"], {"unknown": 1})


if __name__ == "__main__":
    unittest.main()
