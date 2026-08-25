import json
import re
import unittest
from pathlib import Path

from configure_ai_credit_products import (
    CREATE_PRODUCT_URL,
    CREATE_LOCALIZATION_PATH,
    CREATE_PRICE_SCHEDULE_PATH,
    CREATE_AVAILABILITY_PATH,
    LOCALIZATIONS,
    PRODUCTS,
    STOREKIT_CONFIGURATION,
    US_PRICES,
    availability_payload,
    load_localizations,
    load_products,
    load_us_prices,
    localization_payload,
    price_schedule_payload,
    planned_actions,
    planned_localization_actions,
    product_payload,
)


PROJECT_ROOT = Path(__file__).resolve().parent.parent


class ConfigureAICreditProductsTests(unittest.TestCase):
    def test_missing_products_are_created_and_existing_product_is_kept(self) -> None:
        existing = [{
            "id": "existing",
            "attributes": {
                "productId": PRODUCTS[0][0],
                "inAppPurchaseType": "CONSUMABLE",
            },
        }]

        actions = planned_actions(existing)

        self.assertEqual([item[0] for item in actions], ["keep", "create", "create"])

    def test_wrong_existing_type_is_a_conflict(self) -> None:
        actions = planned_actions([{
            "attributes": {
                "productId": PRODUCTS[0][0],
                "inAppPurchaseType": "NON_CONSUMABLE",
            },
        }])

        self.assertEqual(actions[0][0], "conflict")

    def test_create_payload_is_consumable_and_bound_to_bodymode(self) -> None:
        payload = product_payload(PRODUCTS[1][0], PRODUCTS[1][1])
        data = payload["data"]

        self.assertEqual(data["attributes"]["inAppPurchaseType"], "CONSUMABLE")
        self.assertFalse(data["attributes"]["familySharable"])
        self.assertEqual(data["relationships"]["app"]["data"]["id"], "6799871527")
        self.assertEqual(
            CREATE_PRODUCT_URL,
            "https://api.appstoreconnect.apple.com/v2/inAppPurchases",
        )

    def test_storekit_configuration_is_the_creation_contract(self) -> None:
        configured = load_products(STOREKIT_CONFIGURATION)

        self.assertEqual(configured, PRODUCTS)
        self.assertEqual([item[2] for item in configured], [50, 150, 500])

    def test_storekit_us_prices_are_the_release_contract(self) -> None:
        self.assertEqual(load_us_prices(STOREKIT_CONFIGURATION), US_PRICES)
        self.assertEqual(
            US_PRICES,
            {
                "com.yukitoshim.gymtrainingapp.credits50": "1.99",
                "com.yukitoshim.gymtrainingapp.credits150": "4.99",
                "com.yukitoshim.gymtrainingapp.credits500": "12.99",
            },
        )

    def test_storekit_localizations_are_mapped_for_app_store_connect(self) -> None:
        configured = load_localizations(STOREKIT_CONFIGURATION)

        self.assertEqual(configured, LOCALIZATIONS)
        for product_id, values in configured.items():
            self.assertIn(product_id, {item[0] for item in PRODUCTS})
            self.assertEqual({item["locale"] for item in values}, {"ja", "en-US"})
            self.assertTrue(all(item["name"] and item["description"] for item in values))

    def test_localization_plan_detects_missing_matching_and_conflicting_values(self) -> None:
        desired = LOCALIZATIONS[PRODUCTS[0][0]]
        existing = [{"attributes": desired[0]}]

        actions = planned_localization_actions(existing, desired)
        self.assertEqual([item[0] for item in actions], ["keep", "create"])

        changed = [{"attributes": {**desired[0], "description": "different"}}]
        conflict = planned_localization_actions(changed, desired)
        self.assertEqual(conflict[0][0], "conflict")

    def test_localization_payload_is_bound_to_the_v2_product(self) -> None:
        attributes = LOCALIZATIONS[PRODUCTS[1][0]][1]
        payload = localization_payload("resource-id", attributes)
        data = payload["data"]

        self.assertEqual(CREATE_LOCALIZATION_PATH, "/inAppPurchaseLocalizations")
        self.assertEqual(data["type"], "inAppPurchaseLocalizations")
        self.assertEqual(data["attributes"], attributes)
        self.assertEqual(
            data["relationships"]["inAppPurchaseV2"]["data"],
            {"type": "inAppPurchases", "id": "resource-id"},
        )

    def test_price_schedule_payload_uses_one_open_ended_us_base_price(self) -> None:
        payload = price_schedule_payload("product-id", "point-id")

        self.assertEqual(CREATE_PRICE_SCHEDULE_PATH, "/inAppPurchasePriceSchedules")
        self.assertEqual(
            payload["data"]["relationships"]["baseTerritory"]["data"]["id"],
            "USA",
        )
        self.assertIsNone(payload["included"][0]["attributes"]["startDate"])
        self.assertIsNone(payload["included"][0]["attributes"]["endDate"])
        self.assertEqual(
            payload["included"][0]["relationships"]["inAppPurchasePricePoint"]["data"]["id"],
            "point-id",
        )

    def test_availability_payload_enables_every_selected_and_future_territory(self) -> None:
        payload = availability_payload("product-id", ["JPN", "USA"])
        data = payload["data"]

        self.assertEqual(CREATE_AVAILABILITY_PATH, "/inAppPurchaseAvailabilities")
        self.assertTrue(data["attributes"]["availableInNewTerritories"])
        self.assertEqual(
            [item["id"] for item in data["relationships"]["availableTerritories"]["data"]],
            ["JPN", "USA"],
        )

    def test_ios_and_server_credit_mappings_match_storekit_configuration(self) -> None:
        expected = {product_id: credits for product_id, _, credits in PRODUCTS}

        swift_source = (PROJECT_ROOT / "GymTrainingApp/Data/AICreditPurchaseStore.swift").read_text(
            encoding="utf-8"
        )
        swift_ids = set(re.findall(
            r'"(com\.yukitoshim\.gymtrainingapp\.credits[0-9]+)"',
            swift_source,
        ))
        swift_amounts = {
            product_id: int(credits)
            for product_id, credits in re.findall(
                r'case "(com\.yukitoshim\.gymtrainingapp\.credits[0-9]+)": ([0-9]+)',
                swift_source,
            )
        }

        server_source = (PROJECT_ROOT / "local_llm_server/purchase_verifier.py").read_text(
            encoding="utf-8"
        )
        server_amounts = {
            product_id: int(credits)
            for product_id, credits in re.findall(
                r'"(com\.yukitoshim\.gymtrainingapp\.credits[0-9]+)": ([0-9]+)',
                server_source,
            )
        }

        self.assertEqual(swift_ids, set(expected))
        self.assertEqual(swift_amounts, expected)
        self.assertEqual(server_amounts, expected)

    def test_product_registration_document_matches_storekit_prices(self) -> None:
        storekit = json.loads(STOREKIT_CONFIGURATION.read_text(encoding="utf-8"))
        prices = {
            product["productID"]: product["displayPrice"]
            for product in storekit["products"]
        }
        documentation = (
            PROJECT_ROOT / "docs/app_store_connect/ai_credit_products.md"
        ).read_text(encoding="utf-8")

        for product_id, price in prices.items():
            self.assertIn(f"`{product_id}`", documentation)
            self.assertIn(f"${price}", documentation)


if __name__ == "__main__":
    unittest.main()
