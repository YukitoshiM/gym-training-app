#!/usr/bin/env python3
"""Configure BodyMode's free non-EU App Store distribution idempotently."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
METADATA_SCRIPT = ROOT / "scripts/sync_app_store_metadata.py"

EU_TERRITORIES = frozenset({
    "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN",
    "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX",
    "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE",
})


def load_app_store_module():
    spec = importlib.util.spec_from_file_location("bodymode_app_store", METADATA_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load App Store Connect client")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def optional_get(client, path: str) -> dict | None:
    try:
        return client.request("GET", path)
    except RuntimeError as error:
        if "HTTP 404" in str(error):
            return None
        raise


def create_free_price_schedule(client, app_id: str, base_territory: str) -> None:
    points = client.request(
        "GET",
        f"/apps/{app_id}/appPricePoints?filter%5Bterritory%5D={base_territory}&limit=200",
    )["data"]
    free_point = next(
        (point for point in points if float(point["attributes"]["customerPrice"]) == 0),
        None,
    )
    if free_point is None:
        raise RuntimeError(f"No free price point found for {base_territory}")

    local_id = "${free-price}"
    client.request(
        "POST",
        "/appPriceSchedules",
        {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "baseTerritory": {
                        "data": {"type": "territories", "id": base_territory}
                    },
                    "manualPrices": {
                        "data": [{"type": "appPrices", "id": local_id}]
                    },
                },
            },
            "included": [
                {
                    "type": "appPrices",
                    "id": local_id,
                    "attributes": {"startDate": None, "endDate": None},
                    "relationships": {
                        "appPricePoint": {
                            "data": {
                                "type": "appPricePoints",
                                "id": free_point["id"],
                            }
                        }
                    },
                }
            ],
        },
    )


def create_availability(client, app_id: str, territory_ids: list[str]) -> None:
    linkages = []
    included = []
    for territory_id in territory_ids:
        local_id = "${" + territory_id + "}"
        linkages.append({"type": "territoryAvailabilities", "id": local_id})
        included.append(
            {
                "type": "territoryAvailabilities",
                "id": local_id,
                "attributes": {"available": True},
                "relationships": {
                    "territory": {
                        "data": {"type": "territories", "id": territory_id}
                    }
                },
            }
        )

    client.request(
        "POST",
        "https://api.appstoreconnect.apple.com/v2/appAvailabilities",
        {
            "data": {
                "type": "appAvailabilities",
                "attributes": {"availableInNewTerritories": False},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "territoryAvailabilities": {"data": linkages},
                },
            },
            "included": included,
        },
    )


def update_availability(client, availability: dict, desired_territories: set[str]) -> int:
    availability_id = availability["data"]["id"]
    response = client.request(
        "GET",
        f"https://api.appstoreconnect.apple.com/v2/appAvailabilities/{availability_id}/"
        "territoryAvailabilities?limit=200&include=territory",
    )
    changed = 0
    for item in response["data"]:
        territory_id = item["relationships"]["territory"]["data"]["id"]
        desired = territory_id in desired_territories
        if item["attributes"].get("available") is desired:
            continue
        client.request(
            "PATCH",
            f"/territoryAvailabilities/{item['id']}",
            {
                "data": {
                    "type": "territoryAvailabilities",
                    "id": item["id"],
                    "attributes": {"available": desired},
                }
            },
        )
        changed += 1
    return changed


def verify(client, app_id: str, expected_territories: set[str]) -> None:
    app = client.request("GET", f"/apps/{app_id}")["data"]
    prices = client.request(
        "GET",
        f"/appPriceSchedules/{app_id}/manualPrices?include=appPricePoint&limit=200",
    )
    availability = client.request("GET", f"/apps/{app_id}/appAvailabilityV2")["data"]
    availability_id = availability["id"]
    territories_response = client.request(
        "GET",
        f"https://api.appstoreconnect.apple.com/v2/appAvailabilities/{availability_id}/"
        "territoryAvailabilities?limit=200&include=territory",
    )
    available_territories = {
        item["relationships"]["territory"]["data"]["id"]
        for item in territories_response["data"]
        if item["attributes"].get("available") is True
    }
    points_by_id = {
        item["id"]: item
        for item in prices.get("included", [])
        if item["type"] == "appPricePoints"
    }
    current_prices = [
        item
        for item in prices["data"]
        if item["attributes"].get("endDate") is None
    ]
    has_free_price = any(
        float(
            points_by_id[
                item["relationships"]["appPricePoint"]["data"]["id"]
            ]["attributes"]["customerPrice"]
        )
        == 0
        for item in current_prices
    )
    if not has_free_price:
        raise RuntimeError("Current App Store price is not free")
    if available_territories != expected_territories:
        missing = sorted(expected_territories - available_territories)
        unexpected = sorted(available_territories - expected_territories)
        raise RuntimeError(
            f"Territory mismatch: missing={missing}, unexpected={unexpected}"
        )
    if app["attributes"].get("contentRightsDeclaration") != "USES_THIRD_PARTY_CONTENT":
        raise RuntimeError("Content-rights declaration was not applied")
    print("Verified App Store distribution:")
    print("  price: free")
    print(f"  territories: {len(available_territories)}")
    print(f"  EU territories excluded: {len(EU_TERRITORIES)}")
    print(
        "  new territories: "
        + ("enabled" if availability["attributes"].get("availableInNewTerritories") else "disabled")
        + " (EU27 remain explicitly excluded)"
    )
    print("  third-party content rights: declared")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--base-territory", default="JPN")
    args = parser.parse_args()

    module = load_app_store_module()
    client = module.Client(module.jwt(module.DEFAULT_CREDENTIALS))
    app_id = module.APP_ID
    territories = client.request("GET", "/territories?limit=200")["data"]
    territory_ids = sorted(item["id"] for item in territories)
    desired_territories = set(territory_ids) - EU_TERRITORIES
    unknown_eu_ids = EU_TERRITORIES - set(territory_ids)
    if unknown_eu_ids:
        raise RuntimeError(f"EU territories missing from App Store catalog: {sorted(unknown_eu_ids)}")
    price = optional_get(client, f"/apps/{app_id}/appPriceSchedule")
    prices = optional_get(
        client,
        f"/appPriceSchedules/{app_id}/manualPrices?include=appPricePoint&limit=200",
    )
    price_configured = bool(prices and prices.get("data"))
    availability = optional_get(client, f"/apps/{app_id}/appAvailabilityV2")

    print("BodyMode App Store distribution plan")
    print(f"  base territory: {args.base_territory}")
    print("  price: free")
    print(f"  territories: {len(desired_territories)} (EU27 excluded)")
    print("  future territories: preserve the existing App Store Connect setting")
    print("  content rights: uses licensed third-party content")
    if not args.apply:
        print(f"  price schedule: {'configured' if price_configured else 'missing'}")
        print(f"  availability: {'configured' if availability else 'missing'}")
        print("Dry run only. Pass --apply to update App Store Connect.")
        return

    client.request(
        "PATCH",
        f"/apps/{app_id}",
        {
            "data": {
                "type": "apps",
                "id": app_id,
                "attributes": {
                    "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"
                },
            }
        },
    )
    if not price_configured:
        base_territory = args.base_territory
        if price is not None:
            existing_base = optional_get(
                client, f"/appPriceSchedules/{app_id}/baseTerritory"
            )
            if existing_base and existing_base.get("data"):
                base_territory = existing_base["data"]["id"]
        create_free_price_schedule(client, app_id, base_territory)
        print("Created free price schedule.")
    else:
        print("Kept existing price schedule.")
    if availability is None:
        create_availability(client, app_id, sorted(desired_territories))
        print(f"Enabled {len(desired_territories)} non-EU App Store territories.")
    else:
        changed = update_availability(client, availability, desired_territories)
        print(f"Updated App Store availability ({changed} territory changes).")
    verify(client, app_id, desired_territories)


if __name__ == "__main__":
    main()
