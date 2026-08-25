import json
import os
import sys
from pathlib import Path

from usage_analytics import UsageAnalyticsLedger


days = int(sys.argv[1]) if len(sys.argv) > 1 else 30
path = Path(os.getenv(
    "USAGE_ANALYTICS_DB_PATH",
    str(Path.home() / "Library/Application Support/BodyMode/usage-analytics.sqlite3"),
))
print(json.dumps(UsageAnalyticsLedger(path).summary(days=days), ensure_ascii=False, indent=2))
