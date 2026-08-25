import tempfile
import unittest
import sqlite3
from pathlib import Path

from usage_analytics import UsageAnalyticsLedger


class UsageAnalyticsLedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.ledger = UsageAnalyticsLedger(Path(self.temporary_directory.name) / "analytics.sqlite3")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_duplicate_event_is_accepted_once(self) -> None:
        event = {
            "id": "00000000-0000-4000-8000-000000000001",
            "occurred_at": 1_800_000_000,
            "name": "app_opened",
            "dimension": "",
            "app_version": "1.0",
            "locale": "ja_JP",
        }
        self.assertEqual(self.ledger.record("anonymous", [event]), 1)
        self.assertEqual(self.ledger.record("anonymous", [event]), 0)

    def test_summary_contains_only_aggregate_values(self) -> None:
        events = [
            {
                "id": "00000000-0000-4000-8000-000000000001",
                "occurred_at": 1_800_000_000,
                "name": "app_opened",
                "dimension": "",
                "app_version": "1.0",
                "locale": "ja_JP",
            },
            {
                "id": "00000000-0000-4000-8000-000000000002",
                "occurred_at": 1_800_000_050,
                "name": "initial_setup_completed",
                "dimension": "",
                "app_version": "1.0",
                "locale": "ja_JP",
            },
            {
                "id": "00000000-0000-4000-8000-000000000003",
                "occurred_at": 1_800_000_100,
                "name": "daily_action_completed",
                "dimension": "workout",
                "app_version": "1.0",
                "locale": "ja_JP",
            },
        ]
        self.ledger.record("anonymous", events)
        summary = self.ledger.summary(days=30, now=1_800_000_200)

        self.assertEqual(summary["active_users"], 1)
        self.assertEqual(summary["active_user_days"], 1)
        self.assertEqual(summary["north_star_rate"], 1)
        self.assertEqual(summary["milestones"]["initial_setup_completed"]["users"], 1)
        self.assertNotIn("client_key", summary)

    def test_north_star_counts_completed_user_days_not_completion_events(self) -> None:
        events = [
            {
                "id": f"00000000-0000-4000-8000-{index:012d}",
                "occurred_at": 1_800_000_000 + index,
                "name": name,
                "dimension": "workout" if "completed" in name else "",
                "app_version": "1.0",
                "locale": "ja_JP",
            }
            for index, name in enumerate(("app_opened", "daily_action_completed", "daily_action_completed"), start=20)
        ]
        self.ledger.record("anonymous", events)

        summary = self.ledger.summary(days=30, now=1_800_000_200)

        self.assertEqual(summary["active_user_days"], 1)
        self.assertEqual(summary["north_star_completed_user_days"], 1)
        self.assertEqual(summary["north_star_rate"], 1)

    def test_daily_action_summary_groups_allowed_research_properties(self) -> None:
        event = {
            "id": "00000000-0000-4000-8000-000000000010",
            "occurred_at": 1_800_000_000,
            "name": "daily_action_impression",
            "dimension": "workout",
            "properties": {
                "goal": "muscleGain",
                "experience": "beginner",
                "readiness": "normal",
                "actionCategory": "workout",
                "position": 0,
                "source": "localRule",
            },
            "app_version": "22",
            "locale": "ja_JP",
        }
        self.ledger.record("anonymous", [event])

        rows = self.ledger.summary(days=30, now=1_800_000_100)["daily_action_research"]

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["event"], "daily_action_impression")
        self.assertEqual(rows[0]["goal"], "muscleGain")
        self.assertEqual(rows[0]["action_category"], "workout")
        self.assertEqual(rows[0]["position"], 0)
        self.assertEqual(rows[0]["users"], 1)
        self.assertNotIn("client_key", rows[0])

    def test_daily_action_funnel_uses_impression_user_days_as_denominator(self) -> None:
        base_properties = {
            "goal": "muscleGain",
            "experience": "beginner",
            "readiness": "normal",
            "actionCategory": "workout",
            "position": 0,
            "source": "localRule",
        }
        events = []
        sequence = [
            ("daily_action_impression", 1_800_000_000),
            ("home_primary_action_started", 1_800_000_010),
            ("daily_action_completed", 1_800_000_020),
            ("daily_action_impression", 1_800_086_400),
        ]
        for index, (name, timestamp) in enumerate(sequence, start=30):
            events.append({
                "id": f"00000000-0000-4000-8000-{index:012d}",
                "occurred_at": timestamp,
                "name": name,
                "dimension": "workout",
                "properties": base_properties,
                "app_version": "22",
                "locale": "ja_JP",
            })
        self.ledger.record("anonymous", events)

        rows = self.ledger.summary(days=30, now=1_800_086_500)["daily_action_funnel"]

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["impression_user_days"], 2)
        self.assertEqual(rows[0]["started"]["rate"], 0.5)
        self.assertEqual(rows[0]["completed"]["rate"], 0.5)
        self.assertIsNotNone(rows[0]["completed"]["ci95"])
        self.assertTrue(rows[0]["denominator_valid"])

    def test_existing_database_is_migrated_with_empty_properties(self) -> None:
        path = Path(self.temporary_directory.name) / "legacy.sqlite3"
        with sqlite3.connect(path) as connection:
            connection.execute(
                """
                CREATE TABLE usage_events (
                    event_id TEXT PRIMARY KEY,
                    client_key TEXT NOT NULL,
                    occurred_at INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    dimension TEXT NOT NULL,
                    app_version TEXT NOT NULL,
                    locale TEXT NOT NULL
                )
                """
            )
        migrated = UsageAnalyticsLedger(path)

        with sqlite3.connect(path) as connection:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(usage_events)")}
            default_value = connection.execute(
                "SELECT dflt_value FROM pragma_table_info('usage_events') WHERE name = 'properties_json'"
            ).fetchone()[0]

        self.assertIn("properties_json", columns)
        self.assertEqual(default_value, "'{}'")

    def test_summary_includes_by_channel_counts(self) -> None:
        events = [
            {
                "id": "00000000-0000-4000-8000-000000000200",
                "occurred_at": 1_800_000_000,
                "name": "app_opened",
                "dimension": "",
                "app_version": "1.0",
                "locale": "ja_JP",
                "channel": "app_store",
            },
            {
                "id": "00000000-0000-4000-8000-000000000201",
                "occurred_at": 1_800_000_001,
                "name": "app_opened",
                "dimension": "",
                "app_version": "1.0",
                "locale": "ja_JP",
                "channel": "simulator",
            },
            {
                "id": "00000000-0000-4000-8000-000000000202",
                "occurred_at": 1_800_000_002,
                "name": "app_opened",
                "dimension": "",
                "app_version": "1.0",
                "locale": "ja_JP",
            },
        ]
        self.ledger.record("anonymous", events)

        summary = self.ledger.summary(days=30, now=1_800_000_100)
        by_channel = summary["by_channel"]

        self.assertEqual(by_channel["app_store"]["active_users"], 1)
        self.assertEqual(by_channel["app_store"]["active_user_days"], 1)
        self.assertEqual(by_channel["simulator"]["active_users"], 1)
        self.assertEqual(by_channel["simulator"]["active_user_days"], 1)

    def test_summary_includes_anonymous_monetization_funnel(self) -> None:
        events = [
            {
                "id": f"00000000-0000-4000-8000-{index:012d}",
                "occurred_at": 1_800_000_000 + index,
                "name": name,
                "dimension": "50" if name == "credit_purchase_completed" else "",
                "app_version": "22",
                "locale": "en_US",
                "channel": channel,
            }
            for index, (name, channel) in enumerate(
                (
                    ("ai_account_registered", "testflight"),
                    ("ai_credit_insufficient_shown", "testflight"),
                    ("credit_store_opened", "testflight"),
                    ("credit_purchase_completed", "app_store"),
                ),
                start=300,
            )
        ]
        self.ledger.record("anonymous-user", events)

        funnel = self.ledger.summary(days=30, now=1_800_000_500)["monetization_funnel"]["events"]

        self.assertEqual(funnel["ai_account_registered"]["events"], 1)
        self.assertEqual(funnel["credit_store_opened"]["users"], 1)
        self.assertEqual(
            funnel["credit_purchase_completed"]["by_channel"]["app_store"],
            {"events": 1, "users": 1},
        )
        self.assertNotIn("client_key", funnel["credit_purchase_completed"])

    def test_monetization_users_are_not_double_counted_across_channels(self) -> None:
        events = [
            {
                "id": f"00000000-0000-4000-8000-{index:012d}",
                "occurred_at": 1_800_000_000 + index,
                "name": "credit_store_opened",
                "dimension": "",
                "app_version": "22",
                "locale": "en_US",
                "channel": channel,
            }
            for index, channel in enumerate(("testflight", "app_store"), start=400)
        ]
        self.ledger.record("same-user", events)

        event = self.ledger.summary(days=30, now=1_800_000_500)["monetization_funnel"]["events"][
            "credit_store_opened"
        ]

        self.assertEqual(event["events"], 2)
        self.assertEqual(event["users"], 1)
        self.assertEqual(event["by_channel"]["testflight"]["users"], 1)
        self.assertEqual(event["by_channel"]["app_store"]["users"], 1)


if __name__ == "__main__":
    unittest.main()
