import argparse
import json
import os
from pathlib import Path

from usage_analytics import UsageAnalyticsLedger
from usage_quota import AIUsageLedger


def main() -> int:
    parser = argparse.ArgumentParser(description="BodyMode weekly aggregate operations report")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--ad-revenue-jpy", type=float, default=0)
    parser.add_argument("--ai-cost-jpy", type=float, default=0)
    parser.add_argument("--other-cost-jpy", type=float, default=0)
    args = parser.parse_args()

    support = Path.home() / "Library/Application Support/BodyMode"
    analytics_path = Path(os.getenv("USAGE_ANALYTICS_DB_PATH", support / "usage-analytics.sqlite3"))
    ai_usage_path = Path(os.getenv("AI_USAGE_DB_PATH", support / "ai-usage.sqlite3"))
    total_cost = args.ai_cost_jpy + args.other_cost_jpy

    report = {
        "days": max(1, min(args.days, 90)),
        "usage": UsageAnalyticsLedger(analytics_path).summary(days=args.days),
        "ai_operations": AIUsageLedger(ai_usage_path).operational_summary(days=args.days),
        "finance": {
            "ad_revenue_jpy": round(args.ad_revenue_jpy, 2),
            "ai_cost_jpy": round(args.ai_cost_jpy, 2),
            "other_cost_jpy": round(args.other_cost_jpy, 2),
            "net_jpy": round(args.ad_revenue_jpy - total_cost, 2),
        },
        "privacy": "Aggregate reports only; ad and AI data are not joined per user.",
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
