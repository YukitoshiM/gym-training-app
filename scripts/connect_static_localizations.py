#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = ROOT / "docs/localization/translation_packs"


def swift_literal(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    edits: dict[Path, list[tuple[int, str, str, str]]] = defaultdict(list)
    skipped: list[str] = []

    for pack in sorted(PACK_ROOT.glob("translation_source_ja_*.jsonl")):
        for raw_line in pack.read_text(encoding="utf-8").splitlines():
            record = json.loads(raw_line)
            if record["placeholders"]:
                continue
            old = swift_literal(record["source_ja"])
            new = f'L10n.string("{record["id"]}", fallback: {old})'
            for reference in record["source_refs"]:
                path_text, separator, position = reference.rpartition(":")
                if not separator:
                    skipped.append(f"{record['id']} {reference} unsupported-reference")
                    continue
                if not position.isdigit() or not path_text.endswith(".swift"):
                    skipped.append(f"{record['id']} {reference} unsupported-reference")
                    continue
                edits[ROOT / path_text].append((int(position) - 1, old, new, record["id"]))

    changed = 0
    for path, path_edits in edits.items():
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        occupied: set[tuple[int, str]] = set()
        for expected_line, old, new, record_id in path_edits:
            candidates = [
                index
                for index in range(max(0, expected_line - 12), min(len(lines), expected_line + 13))
                if old in lines[index]
            ]
            line_index = expected_line if expected_line < len(lines) and old in lines[expected_line] else None
            if line_index is None and len(candidates) == 1:
                line_index = candidates[0]
            if line_index is None:
                skipped.append(f"{record_id} {path.relative_to(ROOT)}:{expected_line + 1} ambiguous-or-missing")
                continue
            marker = (line_index, old)
            if marker in occupied:
                continue
            lines[line_index] = lines[line_index].replace(old, new, 1)
            occupied.add(marker)
            changed += 1
        if args.apply:
            path.write_text("".join(lines), encoding="utf-8")

    report = ROOT / "docs/localization/static_connection_report.txt"
    report.write_text(
        f"connected={changed}\nskipped={len(skipped)}\n" + "\n".join(skipped) + "\n",
        encoding="utf-8",
    )
    print(f"connected={changed} skipped={len(skipped)} apply={args.apply} report={report.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
