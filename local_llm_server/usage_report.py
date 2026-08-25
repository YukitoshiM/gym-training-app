import json
import os
import sys
from pathlib import Path

from usage_quota import AIUsageLedger


def main() -> int:
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    database_path = Path(
        os.getenv(
            "AI_USAGE_DB_PATH",
            str(Path.home() / "Library/Application Support/BodyMode/ai-usage.sqlite3"),
        )
    )
    ledger = AIUsageLedger(database_path)
    print(
        json.dumps(
            {"days": days, "features": ledger.operational_summary(days=days)},
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
