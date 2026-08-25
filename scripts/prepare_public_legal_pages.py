#!/usr/bin/env python3
"""Render the canonical legal documents into the GitHub Pages layout."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


PAGES = (
    ("privacy-policy-ja.md", "privacy.md", "BodyMode プライバシーポリシー", "/privacy/", "[English]({{ '/en/privacy/' | relative_url }})"),
    ("terms-of-use-ja.md", "terms.md", "BodyMode 利用規約", "/terms/", "[English]({{ '/en/terms/' | relative_url }})"),
    ("support-ja.md", "support.md", "BodyMode サポート", "/support/", "[English]({{ '/en/support/' | relative_url }})"),
    ("privacy-policy-en.md", "en/privacy.md", "BodyMode Privacy Policy", "/en/privacy/", "[日本語]({{ '/privacy/' | relative_url }})"),
    ("terms-of-use-en.md", "en/terms.md", "BodyMode Terms of Use", "/en/terms/", "[日本語]({{ '/terms/' | relative_url }})"),
    ("support-en.md", "en/support.md", "BodyMode Support", "/en/support/", "[日本語]({{ '/support/' | relative_url }})"),
)


def source_digest(source: Path) -> str:
    return hashlib.sha256(source.read_bytes()).hexdigest()


def render(source: Path, title: str, permalink: str, language_link: str) -> str:
    body = source.read_text(encoding="utf-8").strip()
    heading = f"# {title}"
    if not body.startswith(heading):
        raise ValueError(f"{source} must start with {heading!r}")

    lang = "\nlang: en" if permalink.startswith("/en/") else ""
    front_matter = (
        "---\n"
        "layout: page\n"
        f"title: {title}{lang}\n"
        f"permalink: {permalink}\n"
        "---\n\n"
    )
    source_marker = (
        '<meta name="bodymode-legal-source-sha256" '
        f'content="{source_digest(source)}">\n\n'
    )
    remainder = body[len(heading):].lstrip()
    return (
        f"{front_matter}{source_marker}{heading}\n\n"
        f"{language_link}\n\n{remainder}\n"
    )


def prepare(source_dir: Path, output_dir: Path) -> list[Path]:
    written: list[Path] = []
    for source_name, output_name, title, permalink, language_link in PAGES:
        source = source_dir / source_name
        output = output_dir / output_name
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            render(source, title, permalink, language_link), encoding="utf-8"
        )
        written.append(output)
    return written


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "docs" / "legal",
    )
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    for path in prepare(args.source_dir, args.output_dir):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
