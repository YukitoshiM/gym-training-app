#!/usr/bin/env python3
"""Inspect workout export structure without copying personal record values."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from typing import Any


STRONG_REQUIRED = {"date", "workout name", "exercise name", "set order"}
HEVY_REQUIRED = {"title", "start_time", "exercise_title", "set_index"}
SENSITIVE_HEADER_HINTS = {"name", "notes", "description", "memo", "comment"}
DATE_PATTERNS = [
    ("iso_datetime", re.compile(r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?$")),
    ("iso_date", re.compile(r"^\d{4}-\d{2}-\d{2}$")),
    ("day_english_month", re.compile(r"^\d{1,2} [A-Za-z]{3,9} \d{4},? \d{1,2}:\d{2}(?::\d{2})?$")),
    ("english_month", re.compile(r"^[A-Za-z]{3,9} \d{1,2}, \d{4}")),
    ("slash_date", re.compile(r"^\d{1,4}/\d{1,2}/\d{1,4}")),
]


def fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_headers(fieldnames: list[str] | None) -> list[str]:
    return [header.strip().lstrip("\ufeff") for header in (fieldnames or []) if header is not None]


def date_format(value: str) -> str:
    candidate = value.strip()
    if not candidate:
        return "blank"
    for label, pattern in DATE_PATTERNS:
        if pattern.match(candidate):
            if label == "iso_datetime":
                if candidate.endswith("Z") or re.search(r"[+-]\d{2}:?\d{2}$", candidate):
                    return "iso_datetime_with_timezone"
                return "iso_datetime_without_timezone"
            return label
    return "other"


def classify_csv(headers: list[str]) -> str:
    lower = {header.lower() for header in headers}
    if STRONG_REQUIRED <= lower:
        return "strong_csv"
    if HEVY_REQUIRED <= lower:
        return "hevy_workout_csv"
    if "measurement" in " ".join(lower) or {"weight_kg", "body_fat_percentage"} <= lower:
        return "hevy_measurement_csv_candidate"
    return "unknown_csv"


def delimiter_name(delimiter: str) -> str:
    return {",": "comma", ";": "semicolon", "\t": "tab", "|": "pipe"}.get(delimiter, "other")


def audit_csv(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    sample = text[:65536]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t|")
    except csv.Error:
        dialect = csv.excel
    reader = csv.DictReader(text.splitlines(keepends=True), dialect=dialect)
    headers = normalized_headers(reader.fieldnames)
    rows = list(reader)
    lower_to_original = {header.lower(): header for header in headers}
    blanks = Counter()
    set_types = Counter()
    date_formats = Counter()
    set_indices: list[int] = []

    date_columns = [key for key in ("date", "start_time", "end_time") if key in lower_to_original]
    for row in rows:
        for header in headers:
            if not str(row.get(header, "") or "").strip():
                blanks[header] += 1
        for key in date_columns:
            date_formats[date_format(str(row.get(lower_to_original[key], "") or ""))] += 1
        if "set_index" in lower_to_original:
            raw_index = str(row.get(lower_to_original["set_index"], "") or "").strip()
            if re.fullmatch(r"-?\d+", raw_index):
                set_indices.append(int(raw_index))
        elif "set order" in lower_to_original:
            raw_index = str(row.get(lower_to_original["set order"], "") or "").strip()
            if re.fullmatch(r"-?\d+", raw_index):
                set_indices.append(int(raw_index))
        if "set_type" in lower_to_original:
            value = str(row.get(lower_to_original["set_type"], "") or "").strip().lower()
            if value:
                set_types[value] += 1

    lower_headers = {header.lower() for header in headers}
    unit_columns = sorted(header for header in lower_headers if any(token in header for token in ("_kg", "_lbs", "_meters", "_km", "_seconds")))
    sensitive_columns = sorted(
        header for header in headers
        if any(hint in header.lower() for hint in SENSITIVE_HEADER_HINTS)
    )
    return {
        "kind": classify_csv(headers),
        "encoding": "utf-8-sig" if has_bom else "utf-8",
        "newline": "crlf" if b"\r\n" in raw else "lf",
        "delimiter": delimiter_name(dialect.delimiter),
        "headers": headers,
        "row_count": len(rows),
        "blank_counts": dict(sorted(blanks.items())),
        "date_formats": dict(sorted(date_formats.items())),
        "timezone_missing": any(
            key in {"iso_datetime_without_timezone", "day_english_month", "english_month", "slash_date", "other"}
            for key in date_formats
        ),
        "set_index_min": min(set_indices) if set_indices else None,
        "set_index_max": max(set_indices) if set_indices else None,
        "set_index_base_candidate": min(set_indices) if set_indices and min(set_indices) in (0, 1) else None,
        "set_types": dict(sorted(set_types.items())),
        "unit_columns": unit_columns,
        "weight_unit_confirmation_required": "weight" in lower_headers and not any("weight_" in header for header in lower_headers),
        "sensitive_columns_present": sensitive_columns,
    }


def audit_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        return {"kind": "unknown_json", "top_level_type": type(payload).__name__}
    keys = sorted(str(key) for key in payload.keys())
    schema_version = payload.get("schemaVersion")
    kind = "bodymode_json" if schema_version is not None else "unknown_json"
    collection_counts = {
        key: len(value) for key, value in payload.items()
        if isinstance(value, list)
    }
    return {
        "kind": kind,
        "schema_version": schema_version,
        "top_level_keys": keys,
        "collection_counts": dict(sorted(collection_counts.items())),
        "contains_plaintext_photo_data_candidate": any("photo" in key.lower() for key in keys),
    }


def audit_xml(path: Path) -> dict[str, Any]:
    root_tag = None
    record_types = Counter()
    element_counts = Counter()
    for event, element in ET.iterparse(path, events=("start", "end")):
        tag = element.tag.rsplit("}", 1)[-1]
        if root_tag is None and event == "start":
            root_tag = tag
        if event == "end":
            element_counts[tag] += 1
            if tag == "Record":
                record_type = element.attrib.get("type", "unknown")
                record_types[record_type] += 1
            element.clear()
    kind = "apple_health_xml" if root_tag in {"HealthData", "HealthExport"} or record_types else "unknown_xml"
    return {
        "kind": kind,
        "root_tag": root_tag,
        "element_counts": dict(sorted(element_counts.items())),
        "record_type_counts": dict(sorted(record_types.items())),
    }


def audit_file(path: Path) -> dict[str, Any]:
    suffix = path.suffix.lower()
    if suffix == ".csv":
        detail = audit_csv(path)
    elif suffix == ".json":
        detail = audit_json(path)
    elif suffix == ".xml":
        detail = audit_xml(path)
    else:
        detail = {"kind": "unsupported", "suffix": suffix}
    return {
        "file_name": path.name,
        "size_bytes": path.stat().st_size,
        "sha256": fingerprint(path),
        **detail,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    paths: list[Path] = []
    for item in args.inputs:
        if item.is_dir():
            paths.extend(path for path in sorted(item.iterdir()) if path.suffix.lower() in {".csv", ".json", ".xml"})
        else:
            paths.append(item)
    report = {
        "schemaVersion": 1,
        "privacy": "No record cell values are copied into this report.",
        "files": [audit_file(path) for path in paths],
    }
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(output, encoding="utf-8")
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
