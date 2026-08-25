import unittest

from cloudflare_operations_monitor import level_for_exit_code, notification_needed


class CloudflareOperationsMonitorTests(unittest.TestCase):
    def test_maps_report_exit_codes(self) -> None:
        self.assertEqual(level_for_exit_code(0), "ok")
        self.assertEqual(level_for_exit_code(1), "warning")
        self.assertEqual(level_for_exit_code(2), "critical")
        self.assertEqual(level_for_exit_code(70), "critical")

    def test_notifies_on_change_and_periodically_while_unhealthy(self) -> None:
        self.assertTrue(notification_needed({}, "ok", 1_000, 21_600))
        self.assertTrue(notification_needed({"level": "ok", "last_notified_at": 900}, "critical", 1_000, 21_600))
        self.assertFalse(notification_needed({"level": "critical", "last_notified_at": 900}, "critical", 1_000, 21_600))
        self.assertTrue(notification_needed({"level": "critical", "last_notified_at": 900}, "critical", 22_500, 21_600))
        self.assertFalse(notification_needed({"level": "ok", "last_notified_at": 900}, "ok", 99_000, 21_600))


if __name__ == "__main__":
    unittest.main()
