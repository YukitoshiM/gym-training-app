#!/usr/bin/env python3

"""Aggregate privacy manifests from an app, archive, or IPA and verify a baseline."""

from __future__ import annotations

import argparse
import json
import plistlib
import sys
import zipfile
from pathlib import Path
from typing import Any, Iterable


def load_manifests(artifact: Path) -> list[tuple[str, dict[str, Any]]]:
    if artifact.suffix == ".ipa":
        with zipfile.ZipFile(artifact) as archive:
            names = sorted(
                name
                for name in archive.namelist()
                if name.endswith("/PrivacyInfo.xcprivacy")
            )
            return [
                (name, plistlib.loads(archive.read(name)))
                for name in names
            ]

    search_root = artifact / "Products/Applications" if artifact.suffix == ".xcarchive" else artifact
    manifests = sorted(search_root.rglob("PrivacyInfo.xcprivacy"))
    return [
        (str(path.relative_to(search_root)), plistlib.loads(path.read_bytes()))
        for path in manifests
    ]


def aggregate(manifests: Iterable[tuple[str, dict[str, Any]]]) -> dict[str, Any]:
    manifest_list = list(manifests)
    accessed: dict[str, set[str]] = {}
    collected: dict[str, dict[str, Any]] = {}
    root_tracking = False
    tracking_domains: set[str] = set()

    for _, manifest in manifest_list:
        root_tracking = root_tracking or bool(manifest.get("NSPrivacyTracking", False))
        tracking_domains.update(manifest.get("NSPrivacyTrackingDomains", []))

        for item in manifest.get("NSPrivacyAccessedAPITypes", []):
            api_type = item["NSPrivacyAccessedAPIType"]
            accessed.setdefault(api_type, set()).update(
                item.get("NSPrivacyAccessedAPITypeReasons", [])
            )

        for item in manifest.get("NSPrivacyCollectedDataTypes", []):
            data_type = item["NSPrivacyCollectedDataType"]
            current = collected.setdefault(
                data_type,
                {"linked": False, "tracking": False, "purposes": set()},
            )
            current["linked"] = current["linked"] or bool(
                item.get("NSPrivacyCollectedDataTypeLinked", False)
            )
            current["tracking"] = current["tracking"] or bool(
                item.get("NSPrivacyCollectedDataTypeTracking", False)
            )
            current["purposes"].update(
                item.get("NSPrivacyCollectedDataTypePurposes", [])
            )

    normalized_collected = {
        key: {
            "linked": value["linked"],
            "tracking": value["tracking"],
            "purposes": sorted(value["purposes"]),
        }
        for key, value in sorted(collected.items())
    }
    return {
        "manifest_count": len(manifest_list),
        "root_tracking": root_tracking,
        "any_data_type_tracking": any(
            value["tracking"] for value in normalized_collected.values()
        ),
        "tracking_domains": sorted(tracking_domains),
        "accessed_api_types": {
            key: sorted(value) for key, value in sorted(accessed.items())
        },
        "collected_data_types": normalized_collected,
    }


def markdown_report(artifact: Path, manifests: list[tuple[str, dict[str, Any]]], result: dict[str, Any]) -> str:
    lines = [
        "# BodyMode Privacy Manifest Audit",
        "",
        f"Artifact: `{artifact}`",
        f"Manifest count: {result['manifest_count']}",
        f"Root tracking declaration: `{str(result['root_tracking']).lower()}`",
        f"At least one tracked data type: `{str(result['any_data_type_tracking']).lower()}`",
        "",
        "## Included Manifests",
        "",
    ]
    lines.extend(f"- `{name}`" for name, _ in manifests)
    lines.extend(["", "## Collected Data", "", "| Type | Linked | Tracking | Purposes |", "|---|---|---|---|"])
    for data_type, value in result["collected_data_types"].items():
        purposes = ", ".join(value["purposes"])
        lines.append(
            f"| `{data_type}` | {value['linked']} | {value['tracking']} | {purposes} |"
        )
    lines.extend(["", "## Required-Reason APIs", "", "| API type | Reasons |", "|---|---|"])
    for api_type, reasons in result["accessed_api_types"].items():
        lines.append(f"| `{api_type}` | {', '.join(reasons)} |")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    if not args.artifact.exists():
        parser.error(f"artifact does not exist: {args.artifact}")

    manifests = load_manifests(args.artifact)
    if not manifests:
        print("error: no PrivacyInfo.xcprivacy files found", file=sys.stderr)
        return 1

    result = aggregate(manifests)
    report = markdown_report(args.artifact, manifests, result)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report, encoding="utf-8")

    if args.baseline:
        expected = json.loads(args.baseline.read_text(encoding="utf-8"))
        if result != expected:
            print("error: aggregate privacy manifest differs from baseline", file=sys.stderr)
            print(json.dumps(result, indent=2, sort_keys=True), file=sys.stderr)
            return 1

    print(
        f"Privacy manifest audit passed: {result['manifest_count']} manifests, "
        f"{len(result['collected_data_types'])} data types, "
        f"{len(result['accessed_api_types'])} required-reason API types"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
