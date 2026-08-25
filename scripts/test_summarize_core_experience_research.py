import json
import tempfile
import unittest
from pathlib import Path

from summarize_core_experience_research import build_summary, load_sessions, wilson_interval


class CoreResearchSummaryTests(unittest.TestCase):
    def test_deduplicates_sessions_and_does_not_copy_free_text(self):
        session = {
            "participantCode": "P-1",
            "startedAt": "2026-08-16T00:00:00Z",
            "r5Variant": "B",
            "familiarity": "first_time",
            "watchUse": "none",
            "tasks": [
                {
                    "taskID": "r5B",
                    "responses": {"achievement": "private answer", "next": "private next"},
                    "scores": {"achievement": "correct", "next": "incorrect"},
                    "interactionChoice": "完了して閉じる",
                },
                {"taskID": "r9A", "responses": {"action": "private"}, "scores": {"action": "correct", "change": "unscored"}},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.json"
            second = Path(directory) / "second.json"
            payload = {"sessions": [session]}
            first.write_text(json.dumps(payload), encoding="utf-8")
            second.write_text(json.dumps(payload), encoding="utf-8")
            summary = build_summary(load_sessions([first, second]))

        self.assertEqual(summary["session_count"], 1)
        self.assertEqual(summary["r5"]["B"]["achievement"]["correct"], 1)
        self.assertEqual(summary["r5"]["B"]["next"]["incorrect"], 1)
        self.assertFalse(summary["r9"]["action"]["target_met"])
        self.assertFalse(summary["gates"]["r9_each_required_question_at_least_5"])
        self.assertNotIn("private answer", json.dumps(summary))
        self.assertTrue(summary["gates"]["first_time_participant_present"])

    def test_wilson_interval_is_bounded(self):
        self.assertEqual(wilson_interval(0, 0), (0.0, 0.0))
        low, high = wilson_interval(8, 10)
        self.assertGreaterEqual(low, 0)
        self.assertLessEqual(high, 1)
        self.assertLess(low, 0.8)
        self.assertGreater(high, 0.8)


if __name__ == "__main__":
    unittest.main()
