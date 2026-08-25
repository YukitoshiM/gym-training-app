#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALIZATION_ROOT = ROOT / "docs/localization"
SOURCE_ROOT = LOCALIZATION_ROOT / "translation_packs"
TRANSLATION_ROOT = LOCALIZATION_ROOT / "translations"
LOCALES_PATH = LOCALIZATION_ROOT / "target_locales.csv"

OUTPUTS = {
    "iphone": ROOT / "GymTrainingApp/Localizable.xcstrings",
    "watch": ROOT / "GymTrainingWatchApp/Localizable.xcstrings",
    "widget": ROOT / "GymTrainingWatchWidget/Localizable.xcstrings",
}

INFO_OUTPUTS = {
    "iphone": ROOT / "GymTrainingApp/InfoPlist.xcstrings",
    "watch": ROOT / "GymTrainingWatchApp/InfoPlist.xcstrings",
}


def load_release_locales() -> list[str]:
    with LOCALES_PATH.open(encoding="utf-8", newline="") as handle:
        return [
            row["app_store_locale"]
            for row in csv.DictReader(handle)
            if row["app_store_locale"] != "ja"
            and row["translation_strategy"] != "deferred"
        ]


def load_sources() -> dict[str, dict]:
    records: dict[str, dict] = {}
    for path in sorted(SOURCE_ROOT.glob("translation_source_ja_*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            record = json.loads(line)
            if record["id"] in records:
                raise ValueError(f"Duplicate source id: {record['id']}")
            records[record["id"]] = record
    return records


def load_translations(locales: list[str], source_ids: set[str]) -> dict[str, dict[str, dict]]:
    translations: dict[str, dict[str, dict]] = defaultdict(dict)
    for locale in locales:
        for path in sorted((TRANSLATION_ROOT / locale).glob("*.jsonl")):
            for line in path.read_text(encoding="utf-8").splitlines():
                record = json.loads(line)
                record_id = record["id"]
                if record_id not in source_ids:
                    raise ValueError(f"Unknown id for {locale}: {record_id}")
                if record_id in translations[locale]:
                    raise ValueError(f"Duplicate translation for {locale}: {record_id}")
                translations[locale][record_id] = record
        missing = source_ids - translations[locale].keys()
        if missing:
            raise ValueError(f"{locale} is missing {len(missing)} translations")
    return translations


def targets_for(record: dict) -> set[str]:
    targets: set[str] = set()
    for reference in record.get("source_refs", []):
        if reference.startswith("GymTrainingApp/"):
            targets.add("iphone")
        elif reference.startswith("GymTrainingWatchApp/"):
            targets.add("watch")
        elif reference.startswith("GymTrainingWatchWidget/"):
            targets.add("widget")
        elif reference.startswith("Shared/"):
            targets.update(("iphone", "watch"))
    return targets or {"iphone"}


def catalog_entry(record: dict, locales: list[str], translations: dict[str, dict[str, dict]]) -> dict:
    localizations = {
        "ja": {
            "stringUnit": {
                "state": "translated",
                "value": record["source_ja"],
            }
        }
    }
    review_notes: list[str] = []
    for locale in locales:
        translated = translations[locale][record["id"]]
        localizations[locale] = {
            "stringUnit": {
                "state": "translated",
                "value": translated["translation"],
            }
        }
        if translated.get("review_note"):
            review_notes.append(f"{locale}: {translated['review_note']}")

    comments = list(record.get("source_refs", []))
    if record.get("placeholders"):
        comments.append("Placeholders: " + ", ".join(record["placeholders"]))
    comments.extend(review_notes[:5])
    return {
        "comment": "\n".join(comments),
        "extractionState": "manual",
        "localizations": localizations,
    }


def main() -> None:
    locales = load_release_locales()
    sources = load_sources()
    translations = load_translations(locales, set(sources))
    strings_by_target: dict[str, dict[str, dict]] = defaultdict(dict)
    info_strings_by_target: dict[str, dict[str, dict]] = defaultdict(dict)

    for record_id, record in sorted(sources.items()):
        entry = catalog_entry(record, locales, translations)
        for target in targets_for(record):
            strings_by_target[target][record_id] = entry
        for reference in record.get("source_refs", []):
            if ":" not in reference:
                continue
            path_text, property_name = reference.rsplit(":", 1)
            if not property_name.startswith("NS"):
                continue
            if path_text.startswith("GymTrainingApp/"):
                info_strings_by_target["iphone"][property_name] = entry
            elif path_text.startswith("GymTrainingWatchApp/"):
                info_strings_by_target["watch"][property_name] = entry

    for target, output in OUTPUTS.items():
        payload = {
            "sourceLanguage": "ja",
            "strings": strings_by_target[target],
            "version": "1.0",
        }
        output.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"{target}: {len(strings_by_target[target])} keys -> {output.relative_to(ROOT)}")

    for target, output in INFO_OUTPUTS.items():
        payload = {
            "sourceLanguage": "ja",
            "strings": info_strings_by_target[target],
            "version": "1.0",
        }
        output.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"{target}-info: {len(info_strings_by_target[target])} keys -> {output.relative_to(ROOT)}")

    print(f"release_locales={len(locales)} source_records={len(sources)}")


if __name__ == "__main__":
    main()
