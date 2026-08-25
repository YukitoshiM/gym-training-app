#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import time
import urllib.request
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "docs/localization/translation_packs/translation_source_ja_release_delta_01.jsonl"
SOURCE_ROOT = ROOT / "docs/localization/translation_packs"
LOCALES = ROOT / "docs/localization/target_locales.csv"
OUTPUT = ROOT / "docs/localization/translations"
MODEL = os.getenv("BODYMODE_TRANSLATION_MODEL", "translategemma:latest")
PLACEHOLDER_RE = re.compile(r"\{\{value\d+\}\}")


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def release_locales() -> list[dict]:
    with LOCALES.open(encoding="utf-8", newline="") as handle:
        return [
            row for row in csv.DictReader(handle)
            if row["app_store_locale"] != "ja" and row["translation_strategy"] != "deferred"
        ]


def load_translation_memory(locale_id: str, current_source: Path) -> dict[str, str]:
    source_by_id: dict[str, dict] = {}
    for path in sorted(SOURCE_ROOT.glob("translation_source_ja_*.jsonl")):
        if path == current_source:
            continue
        for record in read_jsonl(path):
            source_by_id[record["id"]] = record

    translations_by_text: dict[str, set[str]] = {}
    locale_root = OUTPUT / locale_id
    for path in sorted(locale_root.glob("*.jsonl")):
        for translated in read_jsonl(path):
            original = source_by_id.get(translated["id"])
            if original is None:
                continue
            value = translated.get("translation", "")
            if Counter(PLACEHOLDER_RE.findall(value)) != Counter(original.get("placeholders", [])):
                continue
            translations_by_text.setdefault(original["source_ja"], set()).add(value)
    return {
        source_text: next(iter(values))
        for source_text, values in translations_by_text.items()
        if len(values) == 1
    }


def request_translation(records: list[dict], locale: dict) -> list[dict]:
    source = [{"id": item["id"], "text": item["source_ja"]} for item in records]
    prompt = f"""Translate this Japanese health and fitness app UI into {locale['language_en']} ({locale['app_store_locale']}).
Return only JSON matching the required schema. Preserve every id, order, and placeholders such as {{{{value1}}}} exactly.
Use concise, natural mobile UI wording. Keep medical uncertainty explicit. Do not add explanations.

SOURCE:
{json.dumps(source, ensure_ascii=False)}"""
    schema = {
        "type": "object",
        "properties": {
            "translations": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string"},
                        "translation": {"type": "string"},
                    },
                    "required": ["id", "translation"],
                },
            }
        },
        "required": ["translations"],
    }
    body = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": schema,
        "options": {"temperature": 0.1, "num_ctx": 8192},
    }).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=240) as response:
        result = json.loads(response.read())
    return json.loads(result["response"])["translations"]


def request_placeholder_repair(original: dict, translated: dict, locale: dict) -> dict:
    protected_source = original["source_ja"]
    protected_tokens: dict[str, str] = {}
    for index, placeholder in enumerate(dict.fromkeys(original["placeholders"]), 1):
        protected = f"BODYMODEVALUETOKEN{index}"
        protected_tokens[protected] = placeholder
        protected_source = protected_source.replace(placeholder, protected)
    prompt = f"""Repair one {locale['language_en']} ({locale['app_store_locale']}) mobile UI translation.
The translation must contain every protected token exactly as written. Treat each token as a proper name and place it where the sentence is natural.
Return only JSON matching the schema. Do not add explanations.

Japanese source: {json.dumps(protected_source, ensure_ascii=False)}
Current translation: {json.dumps(translated.get('translation', ''), ensure_ascii=False)}
Required protected tokens: {json.dumps(list(protected_tokens), ensure_ascii=False)}"""
    schema = {
        "type": "object",
        "properties": {
            "id": {"type": "string"},
            "translation": {"type": "string"},
        },
        "required": ["id", "translation"],
    }
    body = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": schema,
        "options": {"temperature": 0.0, "num_ctx": 2048},
    }).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.loads(response.read())
    repaired = json.loads(result["response"])
    repaired["id"] = original["id"]
    for protected, placeholder in protected_tokens.items():
        repaired["translation"] = repaired["translation"].replace(protected, placeholder)
    return repaired


def validate(source: list[dict], translated: list[dict]) -> None:
    if [item["id"] for item in translated] != [item["id"] for item in source]:
        raise ValueError("IDs or order changed")
    for original, result in zip(source, translated):
        expected = Counter(original["placeholders"])
        actual = Counter(PLACEHOLDER_RE.findall(result["translation"]))
        if expected != actual:
            raise ValueError(f"Placeholder mismatch: {original['id']} {expected} != {actual}")
        if not result["translation"].strip():
            raise ValueError(f"Empty translation: {original['id']}")


def normalize_order(source: list[dict], translated: list[dict]) -> list[dict]:
    by_id = {item.get("id"): item for item in translated}
    expected_ids = [item["id"] for item in source]
    if len(by_id) != len(translated) or set(by_id) != set(expected_ids):
        raise ValueError("IDs missing or duplicated")
    return [by_id[record_id] for record_id in expected_ids]


def translate_validated_batch(records: list[dict], locale: dict) -> list[dict]:
    try:
        translated = normalize_order(records, request_translation(records, locale))
    except (KeyError, TypeError, ValueError):
        if len(records) == 1:
            raise
        middle = len(records) // 2
        return (
            translate_validated_batch(records[:middle], locale)
            + translate_validated_batch(records[middle:], locale)
        )
    translated = repair_placeholder_mismatches(records, translated, locale)
    validate(records, translated)
    return translated


def repair_placeholder_mismatches(source: list[dict], translated: list[dict], locale: dict) -> list[dict]:
    repaired = list(translated)
    for index, (original, result) in enumerate(zip(source, repaired)):
        expected = Counter(original["placeholders"])
        actual = Counter(PLACEHOLDER_RE.findall(result["translation"]))
        if expected == actual:
            continue
        if not expected:
            cleaned = PLACEHOLDER_RE.sub("", result["translation"])
            cleaned = re.sub(r"\s+([.,:;!?])", r"\1", cleaned).strip(" -–—:：")
            if cleaned:
                repaired[index] = {**result, "translation": cleaned}
                continue
        last_error: Exception | None = None
        for attempt in range(1, 4):
            try:
                replacement = request_placeholder_repair(original, result, locale)
                replacement_placeholders = Counter(PLACEHOLDER_RE.findall(replacement["translation"]))
                if replacement_placeholders != expected:
                    raise ValueError(f"Placeholder mismatch: {replacement_placeholders}")
                repaired[index] = replacement
                break
            except Exception as error:
                last_error = error
                time.sleep(attempt)
        else:
            # Some small translation models repeatedly omit opaque tokens. Keep
            # the localized copy and restore the required values deterministically.
            text = result["translation"].strip()
            missing = list((expected - actual).elements())
            source_text = original["source_ja"].strip()
            leading: list[str] = []
            trailing: list[str] = []
            middle: list[str] = []
            for placeholder in missing:
                if source_text.startswith(placeholder):
                    leading.append(placeholder)
                elif source_text.endswith(placeholder):
                    trailing.append(placeholder)
                else:
                    middle.append(placeholder)
            restored = " ".join([*leading, text, *middle, *trailing]).strip()
            repaired[index] = {**result, "translation": restored}
    return repaired


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--pack-name")
    parser.add_argument("--batch-size", type=int, default=20)
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error("--batch-size must be positive")

    source = read_jsonl(args.source)
    pack_name = args.pack_name or args.source.name.removeprefix("translation_source_ja_")
    locales = release_locales()
    for index, locale in enumerate(locales, 1):
        locale_id = locale["app_store_locale"]
        output = OUTPUT / locale_id / pack_name
        if output.is_file():
            try:
                existing = read_jsonl(output)
                validate(source, existing)
                print(f"[{index}/{len(locales)}] {locale_id}: existing", flush=True)
                continue
            except Exception:
                pass
        last_error: Exception | None = None
        for attempt in range(1, 4):
            try:
                memory = load_translation_memory(locale_id, args.source)
                translated_by_id = {
                    item["id"]: {"id": item["id"], "translation": memory[item["source_ja"]]}
                    for item in source
                    if item["source_ja"] in memory
                    and Counter(PLACEHOLDER_RE.findall(memory[item["source_ja"]]))
                    == Counter(item["placeholders"])
                }
                pending = [item for item in source if item["id"] not in translated_by_id]
                for start in range(0, len(pending), args.batch_size):
                    batch = pending[start:start + args.batch_size]
                    for translated_item in translate_validated_batch(batch, locale):
                        translated_by_id[translated_item["id"]] = translated_item
                translated = [translated_by_id[item["id"]] for item in source]
                validate(source, translated)
                output.parent.mkdir(parents=True, exist_ok=True)
                rows = [
                    {
                        "id": item["id"],
                        "target_locale": locale_id,
                        "translation": translated_item["translation"],
                        "review_note": "機械翻訳。健康・推定表現は公開前に人手確認が必要です。",
                    }
                    for item, translated_item in zip(source, translated)
                ]
                output.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n", encoding="utf-8")
                print(
                    f"[{index}/{len(locales)}] {locale_id}: translated "
                    f"(memory={len(source) - len(pending)}, model={len(pending)})",
                    flush=True,
                )
                break
            except Exception as error:
                last_error = error
                time.sleep(attempt)
        else:
            raise RuntimeError(f"{locale_id}: {last_error}")


if __name__ == "__main__":
    main()
