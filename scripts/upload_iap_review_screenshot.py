#!/usr/bin/env python3
"""Inspect or upload one App Review screenshot to every BodyMode AI-credit IAP."""

from __future__ import annotations

import argparse
import hashlib
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from configure_ai_credit_products import APP_ID, DEFAULT_CREDENTIALS, PRODUCTS, optional_get  # noqa: E402
from sync_app_store_metadata import Client, jwt  # noqa: E402


DEFAULT_SCREENSHOT = Path("/tmp/bodymode-iap-review.png")
CREATE_PATH = "/inAppPurchaseAppStoreReviewScreenshots"


def create_payload(product_resource_id: str, screenshot: Path) -> dict:
    return {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {
                "fileName": screenshot.name,
                "fileSize": screenshot.stat().st_size,
            },
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {
                        "type": "inAppPurchases",
                        "id": product_resource_id,
                    }
                }
            },
        }
    }


def checksum(screenshot: Path) -> str:
    return hashlib.md5(screenshot.read_bytes()).hexdigest()


def review_screenshot(client: Client, product_resource_id: str) -> dict | None:
    response = optional_get(
        client,
        f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/"
        f"{product_resource_id}/appStoreReviewScreenshot",
    )
    if response is None or response.get("data") is None:
        return None
    return response


def upload(client: Client, product_resource_id: str, screenshot: Path) -> dict:
    created = client.request(
        "POST",
        CREATE_PATH,
        create_payload(product_resource_id, screenshot),
    )["data"]
    resource_id = str(created["id"])
    for operation in created.get("attributes", {}).get("uploadOperations", []):
        client.upload(operation, screenshot)
    client.request(
        "PATCH",
        f"{CREATE_PATH}/{resource_id}",
        {
            "data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "id": resource_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": checksum(screenshot),
                },
            }
        },
    )
    for _ in range(60):
        current = client.request("GET", f"{CREATE_PATH}/{resource_id}")["data"]
        state = current.get("attributes", {}).get("assetDeliveryState", {})
        if state.get("state") == "COMPLETE":
            return current
        if state.get("state") == "FAILED":
            raise RuntimeError(f"App Review screenshot processing failed: {state}")
        time.sleep(2)
    raise TimeoutError("App Review screenshot processing timed out")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", type=Path, default=DEFAULT_CREDENTIALS)
    parser.add_argument("--screenshot", type=Path, default=DEFAULT_SCREENSHOT)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if not args.screenshot.is_file():
        raise SystemExit(f"Screenshot not found: {args.screenshot}")
    if args.screenshot.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
        raise SystemExit("App Review screenshot must be PNG or JPEG")

    client = Client(jwt(args.credentials))
    products = client.request("GET", f"/apps/{APP_ID}/inAppPurchasesV2?limit=200").get("data", [])
    by_product_id = {
        item.get("attributes", {}).get("productId"): item
        for item in products
    }

    missing_products = [product_id for product_id, _, _ in PRODUCTS if product_id not in by_product_id]
    if missing_products:
        raise SystemExit(f"Missing App Store products: {', '.join(missing_products)}")

    pending: list[tuple[str, str]] = []
    for product_id, _, credits in PRODUCTS:
        resource_id = str(by_product_id[product_id]["id"])
        existing = review_screenshot(client, resource_id)
        if existing is None:
            print(f"  create  {credits:>3} credits  {product_id}")
            pending.append((product_id, resource_id))
            continue
        attributes = existing["data"].get("attributes", {})
        state = attributes.get("assetDeliveryState", {}).get("state", "UNKNOWN")
        file_name = attributes.get("fileName", "unknown")
        print(f"  keep    {credits:>3} credits  {product_id}  {file_name}  {state}")

    if not args.apply:
        print(f"Read-only check complete. Missing review screenshots: {len(pending)}")
        return

    for product_id, resource_id in pending:
        completed = upload(client, resource_id, args.screenshot)
        state = completed.get("attributes", {}).get("assetDeliveryState", {}).get("state")
        print(f"  uploaded  {product_id}  {state}")

    remaining = [
        product_id
        for product_id, _, _ in PRODUCTS
        if review_screenshot(client, str(by_product_id[product_id]["id"])) is None
    ]
    if remaining:
        raise SystemExit(f"Review screenshots still missing: {', '.join(remaining)}")
    print("All AI-credit products have an App Review screenshot.")


if __name__ == "__main__":
    main()
