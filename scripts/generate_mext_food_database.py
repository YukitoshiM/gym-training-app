#!/usr/bin/env python3
"""Convert the official MEXT food composition workbook into a bundled JSON catalog."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import openpyxl


SOURCE_NAME = "日本食品標準成分表（八訂）増補2023年"
SOURCE_URL = "https://www.mext.go.jp/a_menu/syokuhinseibun/mext_00001.html"
NUTRIENT_COLUMNS = {
    "calories": 6,
    "protein": 9,
    "fat": 12,
    "carbs": 20,
}


def nutrient(value: object) -> tuple[float, str | None]:
    if value is None:
        return 0.0, "unavailable"
    text = str(value).strip().replace("(", "").replace(")", "")
    if text in {"", "-", "*"}:
        return 0.0, "unavailable"
    if text == "Tr":
        return 0.0, "trace"
    match = re.search(r"-?\d+(?:\.\d+)?", text.replace(",", ""))
    return (float(match.group()), None) if match else (0.0, "unavailable")


def normalized_name(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "").replace("\u3000", " ")).strip()


def convert(source: Path, destination: Path) -> int:
    worksheet = openpyxl.load_workbook(source, read_only=True, data_only=True)["表全体"]
    items: list[dict[str, object]] = []
    for row in worksheet.iter_rows(min_row=13, values_only=True):
        food_group, food_id, _, name = row[:4]
        if not food_id or not name:
            continue
        values: dict[str, float] = {}
        unavailable: list[str] = []
        trace: list[str] = []
        for nutrient_name, column in NUTRIENT_COLUMNS.items():
            value, status = nutrient(row[column])
            values[nutrient_name] = value
            if status == "unavailable":
                unavailable.append(nutrient_name)
            elif status == "trace":
                trace.append(nutrient_name)
        items.append(
            {
                "id": str(food_id),
                "food_group": str(food_group or ""),
                "name": normalized_name(name),
                **values,
                "unavailable_nutrients": unavailable,
                "trace_nutrients": trace,
            }
        )

    payload = {
        "source_name": SOURCE_NAME,
        "source_url": SOURCE_URL,
        "correction_date": "2026-03-27",
        "basis": "可食部100g当たり",
        "attribution": f"{SOURCE_NAME}から引用",
        "items": items,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    return len(items)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    count = convert(arguments.source, arguments.destination)
    print(f"Generated {count} foods at {arguments.destination}")


if __name__ == "__main__":
    main()
