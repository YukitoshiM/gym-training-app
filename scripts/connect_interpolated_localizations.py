#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = ROOT / "docs/localization/translation_packs"


def swift_literal(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def scan_string(source: str, start: int) -> tuple[int, list[str], str] | None:
    if source[start] != '"' or source[start:start + 3] == '\"\"\"':
        return None
    index = start + 1
    expressions: list[str] = []
    template: list[str] = []
    while index < len(source):
        char = source[index]
        if char == '"':
            return index + 1, expressions, "".join(template)
        if char == "\\" and index + 1 < len(source):
            if source[index + 1] != "(":
                template.append(source[index:index + 2])
                index += 2
                continue
            depth = 1
            cursor = index + 2
            expression_start = cursor
            quote: str | None = None
            escaped = False
            while cursor < len(source) and depth:
                current = source[cursor]
                if quote:
                    if escaped:
                        escaped = False
                    elif current == "\\":
                        escaped = True
                    elif current == quote:
                        quote = None
                elif current in {'"', "'"}:
                    quote = current
                elif current == "(":
                    depth += 1
                elif current == ")":
                    depth -= 1
                cursor += 1
            if depth:
                return None
            expressions.append(source[expression_start:cursor - 1].strip())
            template.append(f"{{{{value{len(expressions)}}}}}")
            index = cursor
            continue
        template.append(char)
        index += 1
    return None


def candidates(source: str, template: str) -> list[tuple[int, int, list[str]]]:
    found: list[tuple[int, int, list[str]]] = []
    index = 0
    while index < len(source):
        if source[index] != '"':
            index += 1
            continue
        scanned = scan_string(source, index)
        if scanned is None:
            index += 1
            continue
        end, expressions, candidate_template = scanned
        if expressions and candidate_template == template:
            found.append((index, end, expressions))
        index = end
    return found


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    records = []
    for pack in sorted(PACK_ROOT.glob("translation_source_ja_*.jsonl")):
        for raw_line in pack.read_text(encoding="utf-8").splitlines():
            record = json.loads(raw_line)
            if record["placeholders"]:
                records.append(record)

    by_path: dict[Path, list[dict]] = {}
    skipped: list[str] = []
    for record in records:
        swift_refs = []
        for reference in record["source_refs"]:
            path_text, _, _ = reference.rpartition(":")
            if path_text.endswith(".swift"):
                swift_refs.append(ROOT / path_text)
        for path in set(swift_refs):
            by_path.setdefault(path, []).append(record)

    connected = 0
    for path, path_records in by_path.items():
        source = path.read_text(encoding="utf-8")
        replacements: list[tuple[int, int, str, str]] = []
        occupied: set[tuple[int, int]] = set()
        for record in path_records:
            matches = candidates(source, record["source_ja"])
            matches = [match for match in matches if (match[0], match[1]) not in occupied]
            if len(matches) != 1:
                skipped.append(f'{record["id"]} {path.relative_to(ROOT)} matches={len(matches)}')
                continue
            start, end, expressions = matches[0]
            values = ", ".join(f"String(describing: {expression})" for expression in expressions)
            replacement = (
                f'L10n.string("{record["id"]}", fallback: {swift_literal(record["source_ja"])}, '
                f'values: [{values}])'
            )
            replacements.append((start, end, replacement, record["id"]))
            occupied.add((start, end))

        if args.apply:
            for start, end, replacement, _ in sorted(replacements, reverse=True):
                source = source[:start] + replacement + source[end:]
            path.write_text(source, encoding="utf-8")
        connected += len(replacements)

    report = ROOT / "docs/localization/interpolated_connection_report.txt"
    report.write_text(
        f"connected={connected}\nskipped={len(skipped)}\n" + "\n".join(skipped) + "\n",
        encoding="utf-8",
    )
    print(f"connected={connected} skipped={len(skipped)} apply={args.apply}")


if __name__ == "__main__":
    main()
