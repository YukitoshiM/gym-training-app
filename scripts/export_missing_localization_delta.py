#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "GymTrainingApp": ROOT / "GymTrainingApp/Localizable.xcstrings",
    "GymTrainingWatchApp": ROOT / "GymTrainingWatchApp/Localizable.xcstrings",
    "GymTrainingWatchWidget": ROOT / "GymTrainingWatchWidget/Localizable.xcstrings",
}
CALL_RE = re.compile(
    r'L10n\.string\(\s*"([^"]+)"\s*,\s*fallback:\s*"((?:\\.|[^"\\])*)"',
    re.DOTALL,
)
PLACEHOLDER_RE = re.compile(r"\{\{value\d+\}\}|%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)")


def decoded_swift_literal(value: str) -> str:
    return json.loads(f'"{value}"')


def catalog_keys(path: Path) -> set[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return set(payload.get("strings", {}))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    records: dict[str, dict] = {}
    fallbacks: dict[str, set[str]] = defaultdict(set)
    known_by_target = {target: catalog_keys(path) for target, path in TARGETS.items()}

    for target, known_keys in known_by_target.items():
        source_root = ROOT / target
        for path in sorted(source_root.rglob("*.swift")):
            source = path.read_text(encoding="utf-8")
            for match in CALL_RE.finditer(source):
                record_id = match.group(1)
                if record_id in known_keys:
                    continue
                fallback = decoded_swift_literal(match.group(2))
                fallbacks[record_id].add(fallback)
                line = source.count("\n", 0, match.start()) + 1
                reference = f"{path.relative_to(ROOT)}:{line}"
                record = records.setdefault(
                    record_id,
                    {
                        "id": record_id,
                        "source_locale": "ja",
                        "source_ja": fallback,
                        "context": "BodyMode mobile UI",
                        "placeholders": PLACEHOLDER_RE.findall(fallback),
                        "source_refs": [],
                    },
                )
                record["source_refs"].append(reference)

    conflicts = {key: values for key, values in fallbacks.items() if len(values) > 1}
    if conflicts:
        details = ", ".join(f"{key}={sorted(values)}" for key, values in sorted(conflicts.items()))
        raise ValueError(f"Conflicting fallbacks: {details}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    content = "\n".join(json.dumps(records[key], ensure_ascii=False) for key in sorted(records))
    args.output.write_text(content + ("\n" if content else ""), encoding="utf-8")
    print(f"missing_keys={len(records)} output={args.output}")


if __name__ == "__main__":
    main()
