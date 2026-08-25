#!/usr/bin/env python3
"""Repair Japanese text left in release locales with structured OpenAI output.

The script is resumable: each locale file is replaced atomically as soon as
that locale succeeds. Re-running it processes only translations that still
contain Japanese letters.
"""

from __future__ import annotations

import argparse
import csv
import concurrent.futures
import json
import re
import subprocess
import time
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALIZATION_ROOT = ROOT / "docs/localization"
SOURCE_ROOT = LOCALIZATION_ROOT / "translation_packs"
TRANSLATION_ROOT = LOCALIZATION_ROOT / "translations"
LOCALES_PATH = LOCALIZATION_ROOT / "target_locales.csv"
MODEL = "gpt-5.6-luna"
KEYCHAIN_SERVICE = "com.bodymode.openai-api-key"
KEYCHAIN_ACCOUNT = "bodymode-production"
JAPANESE_LETTER_RE = re.compile(r"[\u3041-\u3096\u30A1-\u30FA]")
PLACEHOLDER_RE = re.compile(r"\{\{value\d+\}\}|%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)")
ENGLISH_INHERITANCE = {"en-AU": "en-US", "en-CA": "en-US", "en-GB": "en-US"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write repaired locale files")
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--batch-size", type=int, default=12)
    parser.add_argument("--concurrency", type=int, default=2)
    return parser.parse_args()


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl_atomic(path: Path, records: list[dict]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
    temporary.replace(path)


def load_sources() -> dict[str, dict]:
    sources: dict[str, dict] = {}
    for path in sorted(SOURCE_ROOT.glob("translation_source_ja_*.jsonl")):
        for record in read_jsonl(path):
            record_id = record["id"]
            if record_id in sources:
                raise ValueError(f"Duplicate source id: {record_id}")
            sources[record_id] = record
    return sources


def load_locale_metadata() -> dict[str, dict]:
    with LOCALES_PATH.open(encoding="utf-8", newline="") as handle:
        return {
            row["app_store_locale"]: row
            for row in csv.DictReader(handle)
            if row["app_store_locale"] != "ja" and row["translation_strategy"] != "deferred"
        }


def locale_files(locale: str) -> list[Path]:
    return sorted((TRANSLATION_ROOT / locale).glob("*.jsonl"))


def load_locale_records(locale: str) -> tuple[dict[str, tuple[Path, int]], dict[Path, list[dict]]]:
    locations: dict[str, tuple[Path, int]] = {}
    files: dict[Path, list[dict]] = {}
    for path in locale_files(locale):
        records = read_jsonl(path)
        files[path] = records
        for index, record in enumerate(records):
            record_id = record["id"]
            if record_id in locations:
                raise ValueError(f"Duplicate translation for {locale}: {record_id}")
            locations[record_id] = (path, index)
    return locations, files


def pending_records(locale: str, sources: dict[str, dict]) -> list[dict]:
    pending: list[dict] = []
    for path in locale_files(locale):
        for record in read_jsonl(path):
            if JAPANESE_LETTER_RE.search(record.get("translation", "")):
                source = sources[record["id"]]
                pending.append(
                    {
                        "id": record["id"],
                        "source": source["source_ja"],
                        "context": source.get("context", "BodyMode app UI"),
                        "placeholders": source.get("placeholders", []),
                    }
                )
    return pending


def production_api_key() -> str:
    completed = subprocess.run(
        [
            "/usr/bin/security",
            "find-generic-password",
            "-a",
            KEYCHAIN_ACCOUNT,
            "-s",
            KEYCHAIN_SERVICE,
            "-w",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    key = completed.stdout.strip()
    if not key.startswith("sk-"):
        raise RuntimeError("Production OpenAI key is unavailable in Keychain")
    return key


def response_text(payload: dict) -> str:
    for item in payload.get("output", []):
        for content in item.get("content", []):
            if content.get("type") == "output_text":
                return str(content.get("text", ""))
    return ""


def request_translations(
    *, api_key: str, model: str, locale: str, language: str, records: list[dict]
) -> tuple[dict[str, str], dict[str, int]]:
    schema = {
        "type": "object",
        "additionalProperties": False,
        "required": ["translations"],
        "properties": {
            "translations": {
                "type": "array",
                "minItems": len(records),
                "maxItems": len(records),
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["id", "translation"],
                    "properties": {
                        "id": {"type": "string"},
                        "translation": {"type": "string"},
                    },
                },
            }
        },
    }
    developer_prompt = (
        f"Translate Japanese BodyMode health and fitness app UI into natural {language} "
        f"for locale {locale}. Keep BodyMode, Apple Watch, HealthKit, RPE, AI, URLs, and "
        "every {{valueN}} or printf placeholder unchanged. Keep buttons concise. Preserve "
        "the exact meaning, uncertainty, privacy promises, purchase conditions, and "
        "non-medical wording. Return every requested id exactly once."
    )
    body = {
        "model": model,
        "store": False,
        "max_output_tokens": 4000,
        "reasoning": {"effort": "low"},
        "input": [
            {"role": "developer", "content": [{"type": "input_text", "text": developer_prompt}]},
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": json.dumps({"locale": locale, "records": records}, ensure_ascii=False),
                    }
                ],
            },
        ],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "bodymode_localization_repair",
                "strict": True,
                "schema": schema,
            }
        },
    }
    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = json.load(response)
            data = json.loads(response_text(payload))
            translated = {item["id"]: item["translation"] for item in data["translations"]}
            expected = {item["id"] for item in records}
            if set(translated) != expected:
                raise ValueError(f"Response id mismatch for {locale}")
            usage = payload.get("usage", {})
            return translated, {
                "input": int(usage.get("input_tokens", 0)),
                "cached": int(usage.get("input_tokens_details", {}).get("cached_tokens", 0)),
                "output": int(usage.get("output_tokens", 0)),
            }
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError) as error:
            last_error = error
            if attempt < 2:
                time.sleep(2**attempt)
    raise RuntimeError(f"OpenAI translation failed for {locale}: {last_error}")


def validate_translation(source: dict, translation: str, locale: str) -> None:
    if not translation.strip():
        raise ValueError(f"Empty translation for {locale}/{source['id']}")
    if JAPANESE_LETTER_RE.search(translation):
        raise ValueError(f"Japanese text remains in {locale}/{source['id']}")
    expected = Counter(source.get("placeholders", []))
    actual = Counter(PLACEHOLDER_RE.findall(translation))
    if actual != expected:
        raise ValueError(
            f"Placeholder mismatch for {locale}/{source['id']}: expected={expected}, actual={actual}"
        )


def apply_translations(locale: str, translated: dict[str, str], sources: dict[str, dict]) -> None:
    locations, files = load_locale_records(locale)
    touched: set[Path] = set()
    for record_id, value in translated.items():
        source = sources[record_id]
        validate_translation(source, value, locale)
        path, index = locations[record_id]
        files[path][index]["translation"] = value
        files[path][index]["review_note"] = (
            "GPT-5.6 Lunaで日本語残留を補修。健康・課金・プライバシー表現は公開後も人手確認対象。"
        )
        touched.add(path)
    for path in sorted(touched):
        write_jsonl_atomic(path, files[path])


def inherited_translations(locale: str, base_locale: str, pending: list[dict]) -> dict[str, str]:
    base_locations, base_files = load_locale_records(base_locale)
    result: dict[str, str] = {}
    for item in pending:
        path, index = base_locations[item["id"]]
        result[item["id"]] = base_files[path][index]["translation"]
    return result


def main() -> int:
    args = parse_args()
    sources = load_sources()
    metadata = load_locale_metadata()
    pending = {locale: pending_records(locale, sources) for locale in metadata}
    pending = {locale: records for locale, records in pending.items() if records}
    print(
        f"affected_locales={len(pending)} affected_records={sum(map(len, pending.values()))}",
        flush=True,
    )
    for locale, records in sorted(pending.items()):
        print(f"  {locale}: {len(records)}", flush=True)
    if not args.apply or not pending:
        return 0

    api_key = production_api_key() if any(locale not in ENGLISH_INHERITANCE for locale in pending) else ""
    totals: defaultdict[str, int] = defaultdict(int)
    inherited_locales = [locale for locale in sorted(pending) if locale in ENGLISH_INHERITANCE]
    for locale in inherited_locales:
        records = pending.pop(locale)
        translated = inherited_translations(locale, ENGLISH_INHERITANCE[locale], records)
        apply_translations(locale, translated, sources)
        print(
            f"repaired {locale}: {len(records)} via inherit:{ENGLISH_INHERITANCE[locale]}; "
            "input=0 cached=0 output=0",
            flush=True,
        )

    batch_size = max(1, min(args.batch_size, 30))

    def repair_locale(locale: str, records: list[dict]) -> dict[str, int]:
        usage_total: defaultdict[str, int] = defaultdict(int)
        for offset in range(0, len(records), batch_size):
            batch = records[offset : offset + batch_size]
            translated, usage = request_translations(
                api_key=api_key,
                model=args.model,
                locale=locale,
                language=metadata[locale]["language_en"],
                records=batch,
            )
            apply_translations(locale, translated, sources)
            for key, value in usage.items():
                usage_total[key] += value
            print(
                f"repaired {locale}: {min(offset + len(batch), len(records))}/{len(records)}; "
                f"input={usage['input']} cached={usage['cached']} output={usage['output']}",
                flush=True,
            )
        return dict(usage_total)

    max_workers = max(1, min(args.concurrency, 3))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(repair_locale, locale, records): locale
            for locale, records in sorted(pending.items())
        }
        for future in concurrent.futures.as_completed(futures):
            locale = futures[future]
            usage = future.result()
            for key, value in usage.items():
                totals[key] += value
            print(
                f"completed {locale}: input={usage.get('input', 0)} "
                f"cached={usage.get('cached', 0)} output={usage.get('output', 0)}",
                flush=True,
            )

    print(
        f"usage input={totals['input']} cached={totals['cached']} "
        f"output={totals['output']} total={totals['input'] + totals['output']}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
