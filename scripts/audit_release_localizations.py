#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import plistlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGET_LOCALES = ROOT / "docs/localization/target_locales.csv"
SOURCE_INFO = ROOT / "GymTrainingApp/Info.plist"
CATALOGS = (
    ROOT / "GymTrainingApp/Localizable.xcstrings",
    ROOT / "GymTrainingWatchApp/Localizable.xcstrings",
    ROOT / "GymTrainingWatchWidget/Localizable.xcstrings",
)
STORE_TO_BUNDLE = {"no": "nb"}


def release_store_locales() -> set[str]:
    with TARGET_LOCALES.open(encoding="utf-8", newline="") as handle:
        rows = csv.DictReader(handle)
        return {
            row["app_store_locale"]
            for row in rows
            if row["translation_strategy"] not in {"deferred"}
        }


def bundle_locales(store_locales: set[str]) -> set[str]:
    return {STORE_TO_BUNDLE.get(locale, locale) for locale in store_locales}


def plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def direct_localizations(bundle: Path) -> set[str]:
    return {path.stem for path in bundle.glob("*.lproj") if path.is_dir()}


def release_bundles(artifact: Path) -> list[Path]:
    if artifact.suffix == ".xcarchive":
        roots = list((artifact / "Products/Applications").glob("*.app"))
    elif artifact.suffix in {".app", ".appex"}:
        roots = [artifact]
    else:
        raise ValueError("artifact must be an .xcarchive, .app, or .appex")

    bundles: list[Path] = []
    for root in roots:
        bundles.append(root)
        bundles.extend(path for path in root.rglob("*") if path.suffix in {".app", ".appex"})
    return sorted(set(bundles))


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit BodyMode release localization declarations.")
    parser.add_argument("artifact", nargs="?", type=Path, help="Optional .xcarchive or app bundle")
    args = parser.parse_args()

    failures: list[str] = []
    store_locales = release_store_locales()
    expected = bundle_locales(store_locales)
    declared = set(plist(SOURCE_INFO).get("CFBundleLocalizations", []))
    if declared != expected:
        failures.append(
            "source CFBundleLocalizations mismatch: "
            f"missing={sorted(expected - declared)} extra={sorted(declared - expected)}"
        )

    for catalog in CATALOGS:
        import json

        data = json.loads(catalog.read_text(encoding="utf-8"))
        catalog_locales = {
            locale
            for entry in data.get("strings", {}).values()
            for locale in entry.get("localizations", {})
        }
        missing = store_locales - catalog_locales
        if missing:
            failures.append(f"{catalog.relative_to(ROOT)} missing locales: {sorted(missing)}")

    checked_bundles: list[Path] = []
    if args.artifact:
        artifact = args.artifact.expanduser().resolve()
        if not artifact.exists():
            failures.append(f"release artifact does not exist: {artifact}")
        else:
            try:
                checked_bundles = release_bundles(artifact)
            except ValueError as error:
                failures.append(str(error))

        bodymode_bundles: list[Path] = []
        for bundle in checked_bundles:
            info_path = bundle / "Info.plist"
            if not info_path.exists():
                continue
            identifier = str(plist(info_path).get("CFBundleIdentifier", ""))
            if identifier.startswith("com.yukitoshim.gymtrainingapp"):
                bodymode_bundles.append(bundle)

        if len(bodymode_bundles) != 3:
            failures.append(f"expected 3 BodyMode app bundles, found {len(bodymode_bundles)}")

        for bundle in bodymode_bundles:
            info = plist(bundle / "Info.plist")
            identifier = str(info.get("CFBundleIdentifier", bundle.name))
            packaged = direct_localizations(bundle)
            if packaged != expected:
                failures.append(
                    f"{identifier} packaged localizations mismatch: "
                    f"missing={sorted(expected - packaged)} extra={sorted(packaged - expected)}"
                )
            plist_declared = set(info.get("CFBundleLocalizations", []))
            if plist_declared and plist_declared != expected:
                failures.append(
                    f"{identifier} CFBundleLocalizations mismatch: "
                    f"missing={sorted(expected - plist_declared)} extra={sorted(plist_declared - expected)}"
                )
            if str(info.get("CFBundleDevelopmentRegion", "")) != "en-US":
                failures.append(f"{identifier} development region must be en-US")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    print(
        f"release_locales={len(store_locales)} bundle_locales={len(expected)} "
        f"bundles={len(checked_bundles) if args.artifact else 0} failures=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
