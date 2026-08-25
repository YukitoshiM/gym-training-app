#!/usr/bin/env python3
"""Verify that every public legal page matches its canonical source document."""

from __future__ import annotations

import argparse
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
import re
import urllib.error
import urllib.request

from prepare_public_legal_pages import PAGES, source_digest


DEFAULT_BASE_URL = "https://yukitoshim.github.io/gym-training-app"
MARKER_PATTERN = re.compile(
    r'<meta\s+name=["\']bodymode-legal-source-sha256["\']\s+'
    r'content=["\']([0-9a-f]{64})["\']\s*/?>',
    re.IGNORECASE,
)


@dataclass(frozen=True)
class PageResult:
    permalink: str
    expected_digest: str
    actual_digest: str | None
    error: str | None = None

    @property
    def passed(self) -> bool:
        return self.error is None and self.actual_digest == self.expected_digest


def fetch_page(url: str, timeout: float) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "BodyMode/1.0 production-legal-preflight"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        return response.read().decode("utf-8")


def marker_digest(payload: str) -> str | None:
    match = MARKER_PATTERN.search(payload)
    return match.group(1).lower() if match else None


def check_pages(
    source_dir: Path,
    base_url: str,
    timeout: float = 15,
    fetcher: Callable[[str, float], str] | None = None,
) -> list[PageResult]:
    load = fetcher or fetch_page
    results: list[PageResult] = []
    for source_name, _, _, permalink, _ in PAGES:
        expected = source_digest(source_dir / source_name)
        url = f"{base_url.rstrip('/')}{permalink}"
        try:
            payload = load(url, timeout)
            actual = marker_digest(payload)
            error = None if actual is not None else "source marker is missing"
        except (OSError, RuntimeError, UnicodeError, urllib.error.URLError) as exc:
            actual = None
            error = str(exc)
        results.append(PageResult(permalink, expected, actual, error))
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "docs" / "legal",
    )
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--timeout", type=float, default=15)
    args = parser.parse_args()

    failed = False
    for result in check_pages(
        args.source_dir, args.base_url, timeout=max(args.timeout, 1)
    ):
        if result.passed:
            print(f"PASS {result.permalink}")
            continue
        failed = True
        detail = result.error or (
            f"published={result.actual_digest} expected={result.expected_digest}"
        )
        print(f"FAIL {result.permalink}: {detail}")

    if failed:
        print("Public legal pages: FAIL")
        return 1
    print("Public legal pages: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
