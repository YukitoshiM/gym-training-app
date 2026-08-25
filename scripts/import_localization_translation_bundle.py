#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALIZATION_DIR = ROOT / "docs/localization"
SOURCE_DIR = LOCALIZATION_DIR / "translation_packs"
DEFAULT_OUTPUT_DIR = LOCALIZATION_DIR / "translations"
TARGET_LOCALES_FILE = LOCALIZATION_DIR / "target_locales.csv"
PLACEHOLDER_RE = re.compile(r"\{\{value\d+\}\}|%(?:\d+\$)?[@dfilsu]")
BUNDLE_NAME_RE = re.compile(r"^translation_(?P<pack>.+)_all_\d+_locales\.jsonl$")

FRAGMENT_REPAIRS = {
    "core_ui.af89edae43f1": {
        "broken_prefix": "))",
        "placeholder_prefix": "{{value1}} ",
        "review_note": (
            "Swift文字列補間で欠落していた件数プレースホルダーを復元しました。"
            "表示時の空白を確認してください。"
        ),
    },
    "core_ui.f369d217b16c": {
        "broken_prefix": ")",
        "placeholder_prefix": "{{value1}}: ",
        "review_note": (
            "Swift文字列補間で欠落していたメニュー名プレースホルダーを復元しました。"
            "画面上の語順を確認してください。"
        ),
    },
}


class ValidationError(Exception):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate and split a multi-locale BodyMode translation bundle."
    )
    parser.add_argument("bundle", type=Path, help="Combined translation JSONL file")
    parser.add_argument(
        "--source",
        type=Path,
        help="Japanese source JSONL. Inferred from the bundle filename when omitted.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Translation output root (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate without writing locale files",
    )
    return parser.parse_args()


def read_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        raise ValidationError(f"File not found: {path}")

    records: list[dict] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValidationError(f"Invalid JSON at {path}:{line_number}: {error}") from error
        if not isinstance(value, dict):
            raise ValidationError(f"Expected an object at {path}:{line_number}")
        records.append(value)
    return records


def infer_source_path(bundle: Path) -> tuple[Path, str]:
    match = BUNDLE_NAME_RE.match(bundle.name)
    if not match:
        raise ValidationError(
            "Could not infer the source pack. Pass --source explicitly or use "
            "translation_<pack>_all_<count>_locales.jsonl."
        )
    pack_name = match.group("pack")
    return SOURCE_DIR / f"translation_source_ja_{pack_name}.jsonl", pack_name


def output_name_for_source(source: Path) -> str:
    prefix = "translation_source_ja_"
    if not source.name.startswith(prefix):
        raise ValidationError(
            f"Source filename must start with {prefix!r}: {source.name}"
        )
    return source.name.removeprefix(prefix)


def load_target_locales(path: Path) -> list[str]:
    if not path.is_file():
        raise ValidationError(f"Target locale list not found: {path}")
    with path.open(encoding="utf-8", newline="") as handle:
        rows = csv.DictReader(handle)
        locales = [
            row["app_store_locale"]
            for row in rows
            if row["app_store_locale"] != "ja"
            and (row.get("translation_strategy") or "full").strip() != "deferred"
        ]
    if not locales:
        raise ValidationError(f"No target locales found in {path}")
    return locales


def validate_source(records: list[dict], path: Path) -> tuple[list[str], dict[str, dict]]:
    required = {"id", "source_locale", "source_ja", "placeholders"}
    source_by_id: dict[str, dict] = {}
    ordered_ids: list[str] = []
    for line_number, record in enumerate(records, 1):
        missing = required - record.keys()
        if missing:
            raise ValidationError(
                f"Missing source keys {sorted(missing)} at {path}:{line_number}"
            )
        record_id = record["id"]
        if not isinstance(record_id, str) or not record_id:
            raise ValidationError(f"Invalid source id at {path}:{line_number}")
        if record_id in source_by_id:
            raise ValidationError(f"Duplicate source id {record_id!r} at {path}:{line_number}")
        if record["source_locale"] != "ja":
            raise ValidationError(f"Unexpected source locale at {path}:{line_number}")
        if not isinstance(record["placeholders"], list) or not all(
            isinstance(value, str) for value in record["placeholders"]
        ):
            raise ValidationError(f"Invalid placeholders at {path}:{line_number}")
        ordered_ids.append(record_id)
        source_by_id[record_id] = record
    return ordered_ids, source_by_id


def repair_known_fragments(record: dict) -> bool:
    repair = FRAGMENT_REPAIRS.get(record["id"])
    if repair is None:
        return False
    broken_prefix = repair["broken_prefix"]
    if record["translation"].startswith(broken_prefix):
        record["translation"] = record["translation"][len(broken_prefix) :].lstrip()
    if "{{value1}}" not in record["translation"]:
        record["translation"] = repair["placeholder_prefix"] + record["translation"]
    record["review_note"] = repair["review_note"]
    return True


def validate_bundle(
    records: list[dict],
    *,
    path: Path,
    expected_locales: list[str],
    ordered_source_ids: list[str],
    source_by_id: dict[str, dict],
) -> tuple[dict[str, list[dict]], int]:
    required = {"id", "target_locale", "translation", "review_note"}
    by_locale: dict[str, list[dict]] = defaultdict(list)
    seen: set[tuple[str, str]] = set()
    repaired_count = 0

    for line_number, original in enumerate(records, 1):
        missing = required - original.keys()
        if missing:
            raise ValidationError(
                f"Missing translation keys {sorted(missing)} at {path}:{line_number}"
            )
        if not all(isinstance(original[key], str) for key in required):
            raise ValidationError(f"Translation values must be strings at {path}:{line_number}")

        record = dict(original)
        record_id = record["id"]
        locale = record["target_locale"]
        if record_id not in source_by_id:
            raise ValidationError(f"Unknown translation id {record_id!r} at {path}:{line_number}")
        if locale not in expected_locales:
            raise ValidationError(f"Unexpected locale {locale!r} at {path}:{line_number}")
        key = (locale, record_id)
        if key in seen:
            raise ValidationError(f"Duplicate translation {locale}/{record_id} at {path}:{line_number}")
        seen.add(key)

        if repair_known_fragments(record):
            repaired_count += 1
        if not record["translation"].strip():
            raise ValidationError(f"Empty translation for {locale}/{record_id}")

        expected_placeholders = Counter(source_by_id[record_id]["placeholders"])
        actual_placeholders = Counter(PLACEHOLDER_RE.findall(record["translation"]))
        if actual_placeholders != expected_placeholders:
            raise ValidationError(
                f"Placeholder mismatch for {locale}/{record_id}: "
                f"expected {dict(expected_placeholders)}, got {dict(actual_placeholders)}"
            )
        by_locale[locale].append(record)

    actual_locales = set(by_locale)
    missing_locales = set(expected_locales) - actual_locales
    extra_locales = actual_locales - set(expected_locales)
    if missing_locales or extra_locales:
        raise ValidationError(
            f"Locale mismatch. Missing: {sorted(missing_locales)}; extra: {sorted(extra_locales)}"
        )

    for locale in expected_locales:
        actual_ids = [record["id"] for record in by_locale[locale]]
        if actual_ids != ordered_source_ids:
            missing_ids = set(ordered_source_ids) - set(actual_ids)
            extra_ids = set(actual_ids) - set(ordered_source_ids)
            raise ValidationError(
                f"Record mismatch for {locale}. Missing: {sorted(missing_ids)}; "
                f"extra: {sorted(extra_ids)}; source order must be preserved."
            )

    return by_locale, repaired_count


def write_locale_files(
    by_locale: dict[str, list[dict]],
    *,
    expected_locales: list[str],
    output_dir: Path,
    output_filename: str,
) -> None:
    for locale in expected_locales:
        locale_dir = output_dir / locale
        locale_dir.mkdir(parents=True, exist_ok=True)
        output_path = locale_dir / output_filename
        temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
        with temporary_path.open("w", encoding="utf-8") as handle:
            for record in by_locale[locale]:
                handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
        temporary_path.replace(output_path)


def main() -> int:
    args = parse_args()
    try:
        inferred_source, inferred_pack_name = infer_source_path(args.bundle)
        source_path = args.source or inferred_source
        output_filename = output_name_for_source(source_path)
        pack_name = output_filename.removesuffix(".jsonl") or inferred_pack_name

        source_records = read_jsonl(source_path)
        ordered_source_ids, source_by_id = validate_source(source_records, source_path)
        expected_locales = load_target_locales(TARGET_LOCALES_FILE)
        bundle_records = read_jsonl(args.bundle)
        by_locale, repaired_count = validate_bundle(
            bundle_records,
            path=args.bundle,
            expected_locales=expected_locales,
            ordered_source_ids=ordered_source_ids,
            source_by_id=source_by_id,
        )

        if not args.validate_only:
            write_locale_files(
                by_locale,
                expected_locales=expected_locales,
                output_dir=args.output_dir,
                output_filename=output_filename,
            )

        review_count = sum(
            bool(record["review_note"])
            for locale_records in by_locale.values()
            for record in locale_records
        )
        action = "Validated" if args.validate_only else "Imported"
        print(
            f"{action} {len(bundle_records):,} records for {len(by_locale)} locales "
            f"from {pack_name}."
        )
        print(
            f"Records per locale: {len(ordered_source_ids)}; "
            f"review notes: {review_count}; repaired source fragments: {repaired_count}."
        )
        if not args.validate_only:
            print(f"Output: {args.output_dir}/<locale>/{output_filename}")
        return 0
    except ValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
