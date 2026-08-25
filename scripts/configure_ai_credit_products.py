#!/usr/bin/env python3
"""Inspect or idempotently configure BodyMode consumable AI-credit products.

The default mode is read-only. ``--apply`` creates missing products,
localizations, US base prices, and global availability. Tax category, review
screenshot, and App Store Server Notifications remain explicit release checks.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from sync_app_store_metadata import Client, jwt  # noqa: E402


APP_ID = "6799871527"
CREATE_PRODUCT_URL = "https://api.appstoreconnect.apple.com/v2/inAppPurchases"
CREATE_LOCALIZATION_PATH = "/inAppPurchaseLocalizations"
CREATE_PRICE_SCHEDULE_PATH = "/inAppPurchasePriceSchedules"
CREATE_AVAILABILITY_PATH = "/inAppPurchaseAvailabilities"
BASE_TERRITORY = "USA"
DEFAULT_CREDENTIALS = Path.home() / "Library/Application Support/BodyMode/AppStoreConnect/config.plist"
STOREKIT_CONFIGURATION = SCRIPT_DIR.parent / "Config" / "BodyMode.storekit"
APP_STORE_LOCALES = {
    "ja_JP": "ja",
    "en_US": "en-US",
}


def load_products(configuration: Path = STOREKIT_CONFIGURATION) -> tuple[tuple[str, str, int], ...]:
    payload = json.loads(configuration.read_text(encoding="utf-8"))
    products = []
    for product in payload.get("products", []):
        product_id = product.get("productID", "")
        match = re.fullmatch(r"com\.yukitoshim\.gymtrainingapp\.credits([1-9][0-9]*)", product_id)
        if match is None:
            raise ValueError(f"Invalid BodyMode credit product identifier: {product_id!r}")
        if product.get("type") != "Consumable":
            raise ValueError(f"Credit product must be consumable: {product_id}")
        reference_name = product.get("referenceName", "").strip()
        if not reference_name:
            raise ValueError(f"Credit product has no reference name: {product_id}")
        products.append((product_id, reference_name, int(match.group(1))))
    if not products:
        raise ValueError("StoreKit configuration contains no AI credit products")
    return tuple(products)


PRODUCTS = load_products()


def load_us_prices(configuration: Path = STOREKIT_CONFIGURATION) -> dict[str, str]:
    payload = json.loads(configuration.read_text(encoding="utf-8"))
    prices = {}
    for product in payload.get("products", []):
        product_id = product.get("productID", "")
        raw_price = str(product.get("displayPrice", "")).strip()
        try:
            price = Decimal(raw_price)
        except Exception as error:
            raise ValueError(f"Invalid US display price for {product_id}: {raw_price!r}") from error
        if price <= 0:
            raise ValueError(f"US display price must be positive for {product_id}")
        prices[product_id] = format(price, "f")
    if set(prices) != {product_id for product_id, _, _ in PRODUCTS}:
        raise ValueError("Every AI credit product must have one US display price")
    return prices


US_PRICES = load_us_prices()


def load_localizations(configuration: Path = STOREKIT_CONFIGURATION) -> dict[str, tuple[dict, ...]]:
    payload = json.loads(configuration.read_text(encoding="utf-8"))
    localizations: dict[str, tuple[dict, ...]] = {}
    for product in payload.get("products", []):
        values = []
        for localization in product.get("localizations", []):
            source_locale = localization.get("locale", "")
            locale = APP_STORE_LOCALES.get(source_locale)
            if locale is None:
                raise ValueError(f"No App Store locale mapping for {source_locale!r}")
            name = localization.get("displayName", "").strip()
            description = localization.get("description", "").strip()
            if not name or not description:
                raise ValueError(f"Incomplete {source_locale} localization for {product['productID']}")
            if len(description) > 55:
                raise ValueError(
                    f"App Store description exceeds 55 characters for "
                    f"{product['productID']} ({source_locale})"
                )
            values.append({"locale": locale, "name": name, "description": description})
        if not values:
            raise ValueError(f"Credit product has no localizations: {product['productID']}")
        localizations[product["productID"]] = tuple(values)
    return localizations


LOCALIZATIONS = load_localizations()


def product_payload(product_id: str, name: str) -> dict:
    return {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": name,
                "productId": product_id,
                "inAppPurchaseType": "CONSUMABLE",
                "familySharable": False,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
            },
        }
    }


def localization_payload(product_resource_id: str, attributes: dict) -> dict:
    return {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": attributes,
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


def price_schedule_payload(
    product_resource_id: str,
    price_point_id: str,
    base_territory: str = BASE_TERRITORY,
) -> dict:
    local_price_id = "${base-price}"
    return {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {
                    "data": {"type": "inAppPurchases", "id": product_resource_id}
                },
                "baseTerritory": {
                    "data": {"type": "territories", "id": base_territory}
                },
                "manualPrices": {
                    "data": [{"type": "inAppPurchasePrices", "id": local_price_id}]
                },
            },
        },
        "included": [{
            "type": "inAppPurchasePrices",
            "id": local_price_id,
            "attributes": {"startDate": None, "endDate": None},
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {"type": "inAppPurchases", "id": product_resource_id}
                },
                "inAppPurchasePricePoint": {
                    "data": {"type": "inAppPurchasePricePoints", "id": price_point_id}
                },
            },
        }],
    }


def availability_payload(product_resource_id: str, territory_ids: list[str]) -> dict:
    return {
        "data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": {
                    "data": {"type": "inAppPurchases", "id": product_resource_id}
                },
                "availableTerritories": {
                    "data": [
                        {"type": "territories", "id": territory_id}
                        for territory_id in territory_ids
                    ]
                },
            },
        }
    }


def optional_get(client: Client, path: str) -> dict | None:
    try:
        return client.request("GET", path)
    except RuntimeError as error:
        if "HTTP 404" in str(error):
            return None
        raise


def price_point_id(client: Client, product_resource_id: str, target_price: str) -> str:
    response = client.request(
        "GET",
        f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/"
        f"{product_resource_id}/pricePoints?filter%5Bterritory%5D={BASE_TERRITORY}&limit=8000",
    )
    target = Decimal(target_price)
    matches = [
        item for item in response.get("data", [])
        if Decimal(item.get("attributes", {}).get("customerPrice", "-1")) == target
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected one {BASE_TERRITORY} price point at {target_price}, found {len(matches)}"
        )
    return str(matches[0]["id"])


def configured_base_price(client: Client, product_resource_id: str) -> str | None:
    schedule = optional_get(
        client,
        f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/"
        f"{product_resource_id}/iapPriceSchedule",
    )
    if schedule is None:
        return None
    schedule_id = schedule["data"]["id"]
    prices = client.request(
        "GET",
        f"/inAppPurchasePriceSchedules/{schedule_id}/manualPrices"
        "?include=inAppPurchasePricePoint&limit=200",
    )
    points = {
        item["id"]: item.get("attributes", {}).get("customerPrice")
        for item in prices.get("included", [])
        if item.get("type") == "inAppPurchasePricePoints"
    }
    current = [
        item for item in prices.get("data", [])
        if item.get("attributes", {}).get("endDate") is None
    ]
    if len(current) != 1:
        raise RuntimeError(
            f"Expected one active base price for product {product_resource_id}, found {len(current)}"
        )
    point_id = current[0]["relationships"]["inAppPurchasePricePoint"]["data"]["id"]
    return str(points[point_id])


def configured_territories(client: Client, product_resource_id: str) -> tuple[set[str], bool] | None:
    availability = optional_get(
        client,
        f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/"
        f"{product_resource_id}/inAppPurchaseAvailability",
    )
    if availability is None:
        return None
    availability_id = availability["data"]["id"]
    territories = client.request(
        "GET",
        f"/inAppPurchaseAvailabilities/{availability_id}/availableTerritories?limit=200",
    )
    return (
        {str(item["id"]) for item in territories.get("data", [])},
        bool(availability["data"].get("attributes", {}).get("availableInNewTerritories")),
    )


def planned_localization_actions(existing: list[dict], desired: tuple[dict, ...]) -> list[tuple[str, dict]]:
    by_locale = {
        item.get("attributes", {}).get("locale"): item.get("attributes", {})
        for item in existing
    }
    actions = []
    for attributes in desired:
        current = by_locale.get(attributes["locale"])
        if current is None:
            actions.append(("create", attributes))
        elif all(current.get(key) == value for key, value in attributes.items()):
            actions.append(("keep", attributes))
        else:
            actions.append(("conflict", attributes))
    return actions


def planned_actions(existing: list[dict]) -> list[tuple[str, str, str, int]]:
    by_product_id = {
        item.get("attributes", {}).get("productId"): item
        for item in existing
    }
    actions = []
    for product_id, name, credits in PRODUCTS:
        current = by_product_id.get(product_id)
        if current is None:
            actions.append(("create", product_id, name, credits))
            continue
        attributes = current.get("attributes", {})
        product_type = attributes.get("inAppPurchaseType")
        if product_type not in (None, "CONSUMABLE"):
            actions.append(("conflict", product_id, name, credits))
        else:
            actions.append(("keep", product_id, name, credits))
    return actions


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", type=Path, default=DEFAULT_CREDENTIALS)
    parser.add_argument("--apply", action="store_true", help="Create missing products")
    args = parser.parse_args()

    client = Client(jwt(args.credentials))
    response = client.request("GET", f"/apps/{APP_ID}/inAppPurchasesV2?limit=200")
    existing_products = response.get("data", [])
    actions = planned_actions(existing_products)
    product_resources = {
        item.get("attributes", {}).get("productId"): item
        for item in existing_products
    }
    territories = client.request("GET", "/territories?limit=200").get("data", [])
    territory_ids = sorted(str(item["id"]) for item in territories)
    if not territory_ids:
        raise SystemExit("App Store territory catalog is empty.")

    print("BodyMode AI credit products")
    for action, product_id, name, credits in actions:
        print(f"  {action:8} {credits:>3} credits  {product_id}  ({name})")
    conflicts = [item for item in actions if item[0] == "conflict"]
    if conflicts:
        raise SystemExit("Existing product type conflict; no changes were made.")

    for action, product_id, name, _ in actions:
        if action == "create" and args.apply:
            created = client.request("POST", CREATE_PRODUCT_URL, product_payload(product_id, name))["data"]
            product_resources[product_id] = created
            print(f"  created  {product_id}")

    localization_conflicts = []
    for product_id, _, _ in PRODUCTS:
        product = product_resources.get(product_id)
        if product is None:
            print(f"  pending  localizations for {product_id} (product must be created first)")
            continue
        product_resource_id = product["id"]
        existing = client.request(
            "GET",
            f"/v2/inAppPurchases/{product_resource_id}/inAppPurchaseLocalizations?limit=200",
        ).get("data", [])
        localization_actions = planned_localization_actions(existing, LOCALIZATIONS[product_id])
        for action, attributes in localization_actions:
            print(f"  {action:8} {product_id}  {attributes['locale']}  {attributes['name']}")
            if action == "conflict":
                localization_conflicts.append((product_id, attributes["locale"]))
            elif action == "create" and args.apply:
                client.request(
                    "POST",
                    CREATE_LOCALIZATION_PATH,
                    localization_payload(product_resource_id, attributes),
                )

    if localization_conflicts:
        raise SystemExit(
            "Existing localization differs from the local contract; no conflicting metadata was overwritten."
        )

    release_conflicts = []
    for product_id, _, _ in PRODUCTS:
        product = product_resources.get(product_id)
        if product is None:
            print(f"  pending  price and availability for {product_id}")
            continue
        resource_id = str(product["id"])
        desired_price = US_PRICES[product_id]
        current_price = configured_base_price(client, resource_id)
        if current_price is None:
            print(f"  create   {product_id}  US base price ${desired_price}")
            if args.apply:
                point_id = price_point_id(client, resource_id, desired_price)
                client.request(
                    "POST",
                    CREATE_PRICE_SCHEDULE_PATH,
                    price_schedule_payload(resource_id, point_id),
                )
        elif Decimal(current_price) == Decimal(desired_price):
            print(f"  keep     {product_id}  US base price ${desired_price}")
        else:
            print(f"  conflict {product_id}  US base price ${current_price} != ${desired_price}")
            release_conflicts.append((product_id, "price"))

        current_availability = configured_territories(client, resource_id)
        if current_availability is None:
            print(f"  create   {product_id}  all {len(territory_ids)} territories")
            if args.apply:
                client.request(
                    "POST",
                    CREATE_AVAILABILITY_PATH,
                    availability_payload(resource_id, territory_ids),
                )
        else:
            current_territories, future_enabled = current_availability
            missing = set(territory_ids) - current_territories
            if not missing and future_enabled:
                print(f"  keep     {product_id}  all {len(territory_ids)} territories")
            else:
                print(
                    f"  conflict {product_id}  missing territories={len(missing)}, "
                    f"future territories={future_enabled}"
                )
                release_conflicts.append((product_id, "availability"))

    if release_conflicts:
        raise SystemExit(
            "Existing price or availability differs from the local contract; no conflicting setting was overwritten."
        )
    if not args.apply:
        print(
            "Read-only check complete. Re-run with --apply after approval to create missing "
            "products, localizations, prices, and availability."
        )
        return
    print(
        "Product records, localizations, prices, and availability are ready. "
        "Configure tax category, review images, and App Store Server Notifications in App Store Connect."
    )


if __name__ == "__main__":
    main()
