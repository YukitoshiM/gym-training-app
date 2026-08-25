#!/usr/bin/env python3
"""Upsert BodyMode store metadata and screenshots without deleting existing assets."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = os.environ.get("BODYMODE_APP_ID", "6799871527")
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "Config/app_store_metadata.json"
DEFAULT_CREDENTIALS = Path.home() / "Library/Application Support/BodyMode/AppStoreConnect/config.plist"


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def jwt(credentials: Path) -> str:
    with credentials.open("rb") as stream:
        config = plistlib.load(stream)
    key_path = Path(config["KeyPath"])
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": config["KeyID"], "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"iss": config["IssuerID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    with tempfile.NamedTemporaryFile() as signature:
        subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path), "-out", signature.name],
            input=signing_input,
            check=True,
        )
        der = Path(signature.name).read_bytes()
    index = 2 + (der[1] & 0x7F if der[1] & 0x80 else 0)
    if der[index] != 2:
        raise ValueError("Invalid ES256 signature")
    index += 1
    r_length = der[index]
    index += 1
    r = der[index:index + r_length]
    index += r_length
    if der[index] != 2:
        raise ValueError("Invalid ES256 signature")
    index += 1
    s_length = der[index]
    index += 1
    s = der[index:index + s_length]
    raw = r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")
    return f"{header}.{payload}.{b64url(raw)}"


class Client:
    def __init__(self, token: str) -> None:
        self.token = token

    def request(self, method: str, path: str, payload: dict | None = None) -> dict:
        url = path if path.startswith("http") else f"{API}{path}"
        data = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self.token}")
        if payload is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            details = error.read().decode(errors="replace")
            raise RuntimeError(f"App Store Connect {method} {path}: HTTP {error.code}\n{details}") from error
        return json.loads(body) if body else {}

    def upload(self, operation: dict, source: Path) -> None:
        offset = operation["offset"]
        length = operation["length"]
        with source.open("rb") as stream:
            stream.seek(offset)
            data = stream.read(length)
        request = urllib.request.Request(operation["url"], data=data, method=operation["method"])
        for header in operation.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        with urllib.request.urlopen(request, timeout=120):
            pass


def relationship(resource_type: str, resource_id: str) -> dict:
    return {"data": {"type": resource_type, "id": resource_id}}


def by_locale(resources: list[dict]) -> dict[str, dict]:
    return {resource["attributes"]["locale"]: resource for resource in resources}


def screenshot_files(config: dict, key: str) -> list[Path]:
    directory = ROOT / config[key]
    return sorted(directory.glob("*.png"))


def validate(config: dict) -> None:
    for locale, values in config["localizations"].items():
        if len(values["name"]) > 30:
            raise ValueError(f"{locale} name exceeds 30 characters")
        if len(values["subtitle"]) > 30:
            raise ValueError(f"{locale} subtitle exceeds 30 characters")
        if len(values["keywords"].encode("utf-8")) > 100:
            raise ValueError(f"{locale} keywords exceed 100 UTF-8 bytes")
        expected = {
            "iphoneScreenshots": 8,
            "ipadScreenshots": 1,
            "watchScreenshots": 3,
        }
        for key, count in expected.items():
            files = screenshot_files(values, key)
            if len(files) != count:
                raise ValueError(f"{locale} {key}: expected {count}, found {len(files)}")
    review_notes_file = config.get("reviewNotesFile")
    if review_notes_file:
        notes = (ROOT / review_notes_file).read_text(encoding="utf-8").strip()
        if len(notes) > 4000:
            raise ValueError(f"App Review notes exceed 4000 characters: {len(notes)}")


def upsert_localization(client: Client, existing: dict | None, resource_type: str, relationship_name: str, parent_resource_type: str, parent_id: str, attributes: dict) -> str:
    if existing:
        resource_id = existing["id"]
        mutable_attributes = {key: value for key, value in attributes.items() if key != "locale"}
        client.request("PATCH", f"/{resource_type}/{resource_id}", {"data": {"type": resource_type, "id": resource_id, "attributes": mutable_attributes}})
        return resource_id
    body = {"data": {"type": resource_type, "attributes": attributes, "relationships": {relationship_name: relationship(parent_resource_type, parent_id)}}}
    return client.request("POST", f"/{resource_type}", body)["data"]["id"]


def ensure_screenshot_set(client: Client, localization_id: str, display_type: str) -> tuple[str, list[dict]]:
    sets = client.request("GET", f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=50")["data"]
    existing = next((item for item in sets if item["attributes"]["screenshotDisplayType"] == display_type), None)
    if existing:
        set_id = existing["id"]
    else:
        body = {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type}, "relationships": {"appStoreVersionLocalization": relationship("appStoreVersionLocalizations", localization_id)}}}
        set_id = client.request("POST", "/appScreenshotSets", body)["data"]["id"]
    screenshots = client.request("GET", f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")["data"]
    return set_id, screenshots


def upload_missing_screenshots(client: Client, set_id: str, existing: list[dict], files: list[Path]) -> None:
    existing_names = {item["attributes"].get("fileName") for item in existing}
    for source in files:
        if source.name in existing_names:
            print(f"    keep {source.name}")
            continue
        body = {"data": {"type": "appScreenshots", "attributes": {"fileName": source.name, "fileSize": source.stat().st_size}, "relationships": {"appScreenshotSet": relationship("appScreenshotSets", set_id)}}}
        created = client.request("POST", "/appScreenshots", body)["data"]
        screenshot_id = created["id"]
        for operation in created["attributes"].get("uploadOperations", []):
            client.upload(operation, source)
        checksum = hashlib.md5(source.read_bytes()).hexdigest()
        client.request("PATCH", f"/appScreenshots/{screenshot_id}", {"data": {"type": "appScreenshots", "id": screenshot_id, "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}})
        for _ in range(60):
            state = client.request("GET", f"/appScreenshots/{screenshot_id}")["data"]["attributes"]["assetDeliveryState"]
            if state.get("state") == "COMPLETE":
                break
            if state.get("state") == "FAILED":
                raise RuntimeError(f"Screenshot processing failed for {source.name}: {state}")
            time.sleep(2)
        else:
            raise TimeoutError(f"Screenshot processing timed out for {source.name}")
        print(f"    uploaded {source.name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--credentials", type=Path, default=DEFAULT_CREDENTIALS)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    validate(config)
    print(f"Validated {len(config['localizations'])} locales for version {config['version']}")
    for locale, values in config["localizations"].items():
        print(f"  {locale}: 8 iPhone, 1 iPad, 3 Watch screenshots")
    if not args.apply:
        print("Dry run only. Pass --apply to update App Store Connect.")
        return

    client = Client(jwt(args.credentials))
    versions = client.request("GET", f"/apps/{APP_ID}/appStoreVersions?limit=50")["data"]
    version = next(item for item in versions if item["attributes"]["platform"] == "IOS" and item["attributes"]["versionString"] == config["version"])
    version_id = version["id"]
    version_attributes = {}
    copyright_value = config.get("copyright")
    if copyright_value:
        version_attributes["copyright"] = copyright_value
    if "usesIdfa" in config:
        version_attributes["usesIdfa"] = bool(config["usesIdfa"])
    if version_attributes:
        client.request(
            "PATCH",
            f"/appStoreVersions/{version_id}",
            {
                "data": {
                    "type": "appStoreVersions",
                    "id": version_id,
                    "attributes": version_attributes,
                }
            },
        )
        print("Updated version declarations and copyright.")
    app_infos = client.request("GET", f"/apps/{APP_ID}/appInfos?limit=50")["data"]
    app_info = next(
        (item for item in app_infos if item["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"),
        app_infos[0],
    )
    app_info_id = app_info["id"]
    primary_category = config.get("primaryCategory")
    if primary_category:
        categories = client.request(
            "GET", "/appCategories?filter%5Bplatforms%5D=IOS&limit=200"
        )["data"]
        if not any(category["id"] == primary_category for category in categories):
            raise ValueError(f"Unknown iOS App Store category: {primary_category}")
        client.request(
            "PATCH",
            f"/appInfos/{app_info_id}",
            {
                "data": {
                    "type": "appInfos",
                    "id": app_info_id,
                    "relationships": {
                        "primaryCategory": relationship(
                            "appCategories", primary_category
                        )
                    },
                }
            },
        )
        print(f"Updated primary category to {primary_category}.")
    age_rating = config.get("ageRating")
    if age_rating:
        declaration = client.request("GET", f"/appInfos/{app_info_id}/ageRatingDeclaration")["data"]
        client.request(
            "PATCH",
            f"/ageRatingDeclarations/{declaration['id']}",
            {
                "data": {
                    "type": "ageRatingDeclarations",
                    "id": declaration["id"],
                    "attributes": age_rating,
                }
            },
        )
        print("Updated age-rating declaration from the release feature inventory.")
    app_localizations = by_locale(client.request("GET", f"/appInfos/{app_info_id}/appInfoLocalizations?limit=50")["data"])
    version_localizations = by_locale(client.request("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")["data"])

    for locale, values in config["localizations"].items():
        print(f"Syncing {locale}")
        app_attributes = {key: values[key] for key in ("locale", "name", "subtitle", "privacyPolicyUrl") if key in values}
        app_attributes["locale"] = locale
        upsert_localization(client, app_localizations.get(locale), "appInfoLocalizations", "appInfo", "appInfos", app_info_id, app_attributes)
        version_localizations = by_locale(
            client.request("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")["data"]
        )
        version_attributes = {key: values[key] for key in ("description", "keywords", "promotionalText", "supportUrl")}
        version_attributes["locale"] = locale
        localization_id = upsert_localization(client, version_localizations.get(locale), "appStoreVersionLocalizations", "appStoreVersion", "appStoreVersions", version_id, version_attributes)
        for display_type, key in (
            ("APP_IPHONE_67", "iphoneScreenshots"),
            ("APP_IPAD_PRO_3GEN_129", "ipadScreenshots"),
            ("APP_WATCH_SERIES_10", "watchScreenshots"),
        ):
            set_id, existing = ensure_screenshot_set(client, localization_id, display_type)
            upload_missing_screenshots(client, set_id, existing, screenshot_files(values, key))

    review_notes_file = config.get("reviewNotesFile")
    if review_notes_file:
        review = client.request("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail")["data"]
        notes = (ROOT / review_notes_file).read_text().strip()
        attributes = {"notes": notes, "demoAccountRequired": False}
        if config.get("reuseBetaReviewContact"):
            beta_review = client.request("GET", f"/apps/{APP_ID}/betaAppReviewDetail").get("data")
            beta_attributes = (beta_review or {}).get("attributes", {})
            contact_fields = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
            missing = [field for field in contact_fields if not beta_attributes.get(field)]
            if missing:
                raise ValueError("Beta Review contact is incomplete; formal review contact was not changed")
            attributes.update({field: beta_attributes[field] for field in contact_fields})
        if review:
            client.request(
                "PATCH",
                f"/appStoreReviewDetails/{review['id']}",
                {"data": {"type": "appStoreReviewDetails", "id": review["id"], "attributes": attributes}},
            )
        else:
            client.request(
                "POST",
                "/appStoreReviewDetails",
                {
                    "data": {
                        "type": "appStoreReviewDetails",
                        "attributes": attributes,
                        "relationships": {"appStoreVersion": relationship("appStoreVersions", version_id)},
                    }
                },
            )
        print("Updated App Review notes and existing Beta Review contact.")
    print("App Store metadata sync complete.")


if __name__ == "__main__":
    main()
