#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
import re
import shutil
import time
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALES = ROOT / "docs/localization/target_locales.csv"
OUTPUT = ROOT / "docs/localization/documents"
MODEL = "translategemma:latest"
DOCUMENTS = {
    "app-store-metadata.md": ROOT / "docs/app_store_connect/app_store_metadata_ja.md",
    "testflight-metadata.md": ROOT / "docs/app_store_connect/testflight_metadata_ja.md",
    "privacy-policy.md": ROOT / "docs/legal/privacy-policy-ja.md",
    "terms-of-use.md": ROOT / "docs/legal/terms-of-use-ja.md",
    "support.md": ROOT / "docs/legal/support-ja.md",
}
INHERITS = {
    "en-AU": "en-US",
    "en-CA": "en-US",
    "en-GB": "en-US",
    "fr-CA": "fr-FR",
    "pt-PT": "pt-BR",
    "es-ES": "es-MX",
}


def release_locales() -> list[dict]:
    with LOCALES.open(encoding="utf-8", newline="") as handle:
        rows = [
            row for row in csv.DictReader(handle)
            if row["app_store_locale"] != "ja" and row["translation_strategy"] != "deferred"
        ]
    base = [row for row in rows if row["app_store_locale"] not in INHERITS]
    inherited = [row for row in rows if row["app_store_locale"] in INHERITS]
    return base + inherited


def request_translation(source: str, locale: dict, document_name: str) -> str:
    purpose = "legally sensitive policy" if document_name in {"privacy-policy.md", "terms-of-use.md"} else "App Store release"
    prompt = f"""Translate the following Japanese BodyMode {purpose} Markdown document into {locale['language_en']} ({locale['app_store_locale']}).
Return only the translated Markdown without a code fence or commentary.
Preserve heading levels, list structure, URLs, email placeholders, product names, technical identifiers, and factual meaning.
Do not add promises, medical claims, legal rights, or omissions. Keep uncertainty and non-medical disclaimers explicit.

--- BEGIN DOCUMENT ---
{source}
--- END DOCUMENT ---"""
    body = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.05, "num_ctx": 32768},
    }).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=1_200) as response:
        result = json.loads(response.read())
    translated = result["response"].strip()
    if translated.startswith("```"):
        translated = re.sub(r"^```(?:markdown)?\s*", "", translated)
        translated = re.sub(r"\s*```$", "", translated)
    return translated.strip() + "\n"


def validate(source: str, translated: str, document_name: str) -> None:
    if len(translated.strip()) < max(100, len(source) // 5):
        raise ValueError("Translation is unexpectedly short")
    source_headings = re.findall(r"^#{1,6}\s", source, flags=re.MULTILINE)
    target_headings = re.findall(r"^#{1,6}\s", translated, flags=re.MULTILINE)
    if len(source_headings) != len(target_headings):
        raise ValueError(f"Heading count changed: {len(source_headings)} -> {len(target_headings)}")
    for url in re.findall(r"https?://[^\s)>]+", source):
        if url not in translated:
            raise ValueError(f"URL changed or removed: {url}")
    if "BodyMode" in source and "BodyMode" not in translated:
        raise ValueError(f"BodyMode removed from {document_name}")


def translate_document(source: str, locale: dict, document_name: str) -> str:
    last_error: Exception | None = None
    for attempt in range(1, 4):
        try:
            translated = request_translation(source, locale, document_name)
            validate(source, translated, document_name)
            return translated
        except Exception as error:
            last_error = error
            time.sleep(attempt * 2)
    raise RuntimeError(f"{locale['app_store_locale']}/{document_name}: {last_error}")


def main() -> None:
    sources = {name: path.read_text(encoding="utf-8") for name, path in DOCUMENTS.items()}
    statuses: list[dict] = []
    locales = release_locales()
    for locale_index, locale in enumerate(locales, 1):
        locale_id = locale["app_store_locale"]
        locale_dir = OUTPUT / locale_id
        locale_dir.mkdir(parents=True, exist_ok=True)
        inherited_from = INHERITS.get(locale_id)
        for document_index, (name, source) in enumerate(sources.items(), 1):
            output = locale_dir / name
            if output.is_file():
                try:
                    validate(source, output.read_text(encoding="utf-8"), name)
                    print(f"[{locale_index}/43 {document_index}/5] {locale_id}/{name}: existing", flush=True)
                    continue
                except Exception:
                    pass
            if inherited_from:
                inherited_path = OUTPUT / inherited_from / name
                if not inherited_path.is_file():
                    raise RuntimeError(f"Missing inherited draft: {inherited_path}")
                shutil.copyfile(inherited_path, output)
                print(f"[{locale_index}/43 {document_index}/5] {locale_id}/{name}: inherited {inherited_from}", flush=True)
            else:
                output.write_text(translate_document(source, locale, name), encoding="utf-8")
                print(f"[{locale_index}/43 {document_index}/5] {locale_id}/{name}: translated", flush=True)
        statuses.append({
            "locale": locale_id,
            "documents": list(DOCUMENTS),
            "status": "machine_draft_human_review_required",
            "inherited_from": inherited_from,
        })
    (OUTPUT / "status.json").write_text(
        json.dumps({
            "source_locale": "ja",
            "locale_count": len(locales),
            "documents_per_locale": len(DOCUMENTS),
            "human_review_required": ["legal meaning", "health claims", "regional wording", "store character limits"],
            "locales": statuses,
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
