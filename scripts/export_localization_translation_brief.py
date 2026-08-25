#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import plistlib
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "docs/localization/translation_packs"
MAX_RECORDS_PER_PACK = 250
JAPANESE_RE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff]")
STRING_RE = re.compile(r'(?<!#)"((?:\\.|[^"\\])*)"')
PRINTF_RE = re.compile(r"%(?:\d+\$)?[@dfilsu]")

EXCLUDED_SWIFT_FILES = {
    "GymTrainingApp/Data/CoachContextBuilder.swift",
    "GymTrainingApp/Support/AppDiagnostics.swift",
    "GymTrainingApp/Features/Settings/LegalAndSupportViews.swift",
}

PACK_ORDER = [
    "core_ui",
    "training",
    "health_meals_body_ai",
    "watch_widget",
    "domain_catalog",
    "runtime_messages",
    "permissions",
]


def pack_for(path: str) -> str:
    if path.endswith("Info.plist"):
        return "permissions"
    if path.startswith("GymTrainingWatch"):
        return "watch_widget"
    if "/Domain/" in path or path.endswith("Data/PresetExerciseStore.swift"):
        return "domain_catalog"
    if any(
        marker in path
        for marker in (
            "/Features/Plans/",
            "/Features/Workout/",
            "/Features/Exercises/",
            "/Features/History/",
            "Data/AppStore+Workout.swift",
            "Data/WatchPlanSyncService.swift",
        )
    ):
        return "training"
    if any(
        marker in path
        for marker in (
            "/Features/Health/",
            "/Features/Meals/",
            "/Features/Body",
            "/Features/Reports/",
            "Data/LocalAIClient.swift",
            "Data/DailyRecommendation",
            "Data/HealthDataManager.swift",
        )
    ):
        return "health_meals_body_ai"
    if any(
        marker in path
        for marker in (
            "/App/",
            "/Features/Home/",
            "/Features/Onboarding/",
            "/Features/Record/",
            "/Features/Settings/",
            "/Features/Shared/",
            "/Advertising/",
            "/Support/",
        )
    ):
        return "core_ui"
    return "runtime_messages"


def mask_interpolations(value: str) -> tuple[str, list[str]]:
    output: list[str] = []
    placeholders: list[str] = []
    index = 0
    while index < len(value):
        if value.startswith(r"\(", index):
            depth = 1
            cursor = index + 2
            while cursor < len(value) and depth:
                if value[cursor] == "(":
                    depth += 1
                elif value[cursor] == ")":
                    depth -= 1
                cursor += 1
            if depth == 0:
                token = f"{{{{value{len(placeholders) + 1}}}}}"
                placeholders.append(token)
                output.append(token)
                index = cursor
                continue
        output.append(value[index])
        index += 1

    normalized = "".join(output)
    normalized = normalized.replace(r"\n", "\n").replace(r'\"', '"')
    normalized = normalized.replace(r"\t", "\t").replace(r"\\", "\\")
    for token in PRINTF_RE.findall(normalized):
        if token not in placeholders:
            placeholders.append(token)
    return normalized.strip(), placeholders


def add_record(
    records: dict[tuple[str, str], dict],
    *,
    pack: str,
    source: str,
    source_ref: str,
) -> None:
    normalized, placeholders = mask_interpolations(source)
    if not normalized or not JAPANESE_RE.search(normalized):
        return
    key = (pack, normalized)
    if key not in records:
        digest = hashlib.sha256(f"{pack}\0{normalized}".encode()).hexdigest()[:12]
        records[key] = {
            "id": f"{pack}.{digest}",
            "source_locale": "ja",
            "source_ja": normalized,
            "placeholders": placeholders,
            "source_refs": [source_ref],
        }
    elif source_ref not in records[key]["source_refs"]:
        records[key]["source_refs"].append(source_ref)


def collect_swift(records: dict[tuple[str, str], dict]) -> None:
    roots = [
        ROOT / "GymTrainingApp",
        ROOT / "GymTrainingWatchApp",
        ROOT / "GymTrainingWatchWidget",
        ROOT / "Shared",
    ]
    for source_root in roots:
        if not source_root.exists():
            continue
        for path in sorted(source_root.rglob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            if relative in EXCLUDED_SWIFT_FILES:
                continue
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line.lstrip().startswith("//"):
                    continue
                for match in STRING_RE.finditer(line):
                    add_record(
                        records,
                        pack=pack_for(relative),
                        source=match.group(1),
                        source_ref=f"{relative}:{line_number}",
                    )


def collect_permissions(records: dict[tuple[str, str], dict]) -> None:
    for relative in ("GymTrainingApp/Info.plist", "GymTrainingWatchApp/Info.plist"):
        path = ROOT / relative
        if not path.exists():
            continue
        with path.open("rb") as handle:
            values = plistlib.load(handle)
        for key, value in sorted(values.items()):
            if key.startswith("NS") and key.endswith("UsageDescription") and isinstance(value, str):
                add_record(
                    records,
                    pack="permissions",
                    source=value,
                    source_ref=f"{relative}:{key}",
                )


def write_packs(records: dict[tuple[str, str], dict]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for old_file in OUTPUT_DIR.glob("translation_source_ja_*.jsonl"):
        old_file.unlink()

    grouped: dict[str, list[dict]] = defaultdict(list)
    for (pack, _), record in records.items():
        record["source_refs"].sort()
        grouped[pack].append(record)

    manifest = {
        "source_locale": "ja",
        "max_records_per_file": MAX_RECORDS_PER_PACK,
        "excluded_from_translation": sorted(EXCLUDED_SWIFT_FILES),
        "packs": [],
    }
    for pack in PACK_ORDER:
        entries = sorted(grouped.get(pack, []), key=lambda item: (item["source_ja"], item["id"]))
        for offset in range(0, len(entries), MAX_RECORDS_PER_PACK):
            part = offset // MAX_RECORDS_PER_PACK + 1
            chunk = entries[offset : offset + MAX_RECORDS_PER_PACK]
            filename = f"translation_source_ja_{pack}_{part:02d}.jsonl"
            output_path = OUTPUT_DIR / filename
            with output_path.open("w", encoding="utf-8") as handle:
                for record in chunk:
                    handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
            manifest["packs"].append(
                {
                    "file": filename,
                    "category": pack,
                    "records": len(chunk),
                }
            )

    manifest["total_records"] = sum(item["records"] for item in manifest["packs"])
    with (OUTPUT_DIR / "index.json").open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main() -> None:
    records: dict[tuple[str, str], dict] = {}
    collect_swift(records)
    collect_permissions(records)
    write_packs(records)
    print(f"Exported {len(records)} translation records to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
