#!/usr/bin/env python3
"""Select a processed build for an App Store version without submitting review."""

from __future__ import annotations

import argparse
import importlib.util
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/sync_app_store_metadata.py"


def load_asc_module():
    spec = importlib.util.spec_from_file_location("bodymode_asc", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load App Store Connect client")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("build_number")
    parser.add_argument("--version", default="1.0")
    parser.add_argument("--wait", type=int, default=0, help="Seconds to wait for VALID processing state")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    asc = load_asc_module()
    client = asc.Client(asc.jwt(asc.DEFAULT_CREDENTIALS))
    deadline = time.monotonic() + args.wait
    build = None
    while True:
        builds = client.request("GET", f"/builds?filter%5Bapp%5D={asc.APP_ID}&limit=200&sort=-uploadedDate")["data"]
        build = next((item for item in builds if item["attributes"]["version"] == args.build_number), None)
        if build and build["attributes"]["processingState"] == "VALID":
            break
        state = build["attributes"]["processingState"] if build else "NOT_VISIBLE"
        print(f"Build {args.build_number}: {state}", flush=True)
        if time.monotonic() >= deadline:
            raise SystemExit(2)
        time.sleep(15)

    versions = client.request("GET", f"/apps/{asc.APP_ID}/appStoreVersions?limit=50")["data"]
    version = next(
        item for item in versions
        if item["attributes"]["platform"] == "IOS" and item["attributes"]["versionString"] == args.version
    )
    current = client.request("GET", f"/appStoreVersions/{version['id']}/build").get("data")
    if current and current["id"] == build["id"]:
        print(f"App Store version {args.version} already uses Build {args.build_number}.")
        return
    print(f"Ready to select Build {args.build_number} for App Store version {args.version}.")
    if not args.apply:
        print("Dry run only. Pass --apply to update App Store Connect.")
        return
    client.request(
        "PATCH",
        f"/appStoreVersions/{version['id']}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    print(f"Selected Build {args.build_number} for App Store version {args.version}.")


if __name__ == "__main__":
    main()
