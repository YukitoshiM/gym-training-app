#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cloudflare_operations_report import render_report, report_exit_code


class OperationsReportTests(unittest.TestCase):
    def report(self, *, health="ok", operations="ok"):
        return {
            "health": {"http_status": 200 if health == "ok" else 503, "status": health, "model": "luna"},
            "operations": {
                "status": operations,
                "ai": {
                    "completed": 9,
                    "total": 10,
                    "success_rate": 0.9,
                    "p95_duration_ms": 1200,
                    "daily_request_limit": 500,
                    "daily_request_utilization": 0.02,
                },
                "credits": {"pending_reservations": 0, "stale_pending_reservations": 0, "invariant_anomalies": 0},
                "app_store_notifications": {"processed": 1, "rejected": 0},
                "alerts": [],
            },
        }

    def test_exit_code_reflects_health_and_operations(self):
        self.assertEqual(report_exit_code(self.report()), 0)
        self.assertEqual(report_exit_code(self.report(operations="warning")), 1)
        self.assertEqual(report_exit_code(self.report(operations="critical")), 2)
        self.assertEqual(report_exit_code(self.report(health="degraded")), 2)
        self.assertEqual(report_exit_code(self.report(health="degraded"), True), 1)

    def test_render_is_compact_and_contains_no_credentials(self):
        rendered = render_report(self.report())
        self.assertIn("AI 24h: 9/10", rendered)
        self.assertIn("Alerts: none", rendered)
        self.assertNotIn("access_token", rendered)


if __name__ == "__main__":
    unittest.main()
