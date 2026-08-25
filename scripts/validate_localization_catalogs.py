#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALES = ROOT / "docs/localization/target_locales.csv"
TARGETS = {
    "GymTrainingApp": ROOT / "GymTrainingApp/Localizable.xcstrings",
    "GymTrainingWatchApp": ROOT / "GymTrainingWatchApp/Localizable.xcstrings",
    "GymTrainingWatchWidget": ROOT / "GymTrainingWatchWidget/Localizable.xcstrings",
}
KEY_RE = re.compile(r'L10n\.string\(\s*"([^"]+)"')
PLACEHOLDER_RE = re.compile(r"\{\{value\d+\}\}|%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)")
JAPANESE_LETTER_RE = re.compile(r"[\u3041-\u3096\u30A1-\u30FA]")


def release_locales() -> set[str]:
    with LOCALES.open(encoding="utf-8", newline="") as handle:
        return {
            row["app_store_locale"]
            for row in csv.DictReader(handle)
            if row["translation_strategy"] != "deferred"
        }


def explicit_keys(root: Path) -> set[str]:
    keys: set[str] = set()
    for path in root.rglob("*.swift"):
        keys.update(KEY_RE.findall(path.read_text(encoding="utf-8")))
    return keys


def main() -> int:
    expected_locales = release_locales()
    failures: list[str] = []

    for target, catalog_path in TARGETS.items():
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        strings = catalog.get("strings", {})
        missing_keys = sorted(explicit_keys(ROOT / target) - strings.keys())
        if missing_keys:
            failures.append(f"{target}: missing explicit keys: {', '.join(missing_keys)}")

        for key, entry in strings.items():
            localizations = entry.get("localizations", {})
            missing_locales = expected_locales - localizations.keys()
            if missing_locales:
                failures.append(f"{target}:{key}: missing locales: {','.join(sorted(missing_locales))}")
                continue
            source_value = localizations["ja"]["stringUnit"]["value"]
            expected_placeholders = Counter(PLACEHOLDER_RE.findall(source_value))
            for locale in expected_locales - {"ja"}:
                value = localizations[locale]["stringUnit"]["value"]
                if not value.strip():
                    failures.append(f"{target}:{key}:{locale}: empty translation")
                elif Counter(PLACEHOLDER_RE.findall(value)) != expected_placeholders:
                    failures.append(f"{target}:{key}:{locale}: placeholder mismatch")
                elif JAPANESE_LETTER_RE.search(value):
                    failures.append(f"{target}:{key}:{locale}: untranslated Japanese text")

        print(f"{target}: keys={len(strings)} explicit_missing={len(missing_keys)}")

    if failures:
        print(f"failures={len(failures)}")
        for failure in failures[:100]:
            print(failure)
        return 1
    print(f"release_locales={len(expected_locales)} failures=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
