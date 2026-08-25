import plistlib
import tempfile
import unittest
from pathlib import Path

from audit_privacy_manifests import aggregate, load_manifests


class PrivacyManifestAuditTests(unittest.TestCase):
    def test_aggregates_strictest_data_declaration(self) -> None:
        manifests = [
            (
                "App/PrivacyInfo.xcprivacy",
                {
                    "NSPrivacyTracking": False,
                    "NSPrivacyCollectedDataTypes": [
                        {
                            "NSPrivacyCollectedDataType": "DeviceID",
                            "NSPrivacyCollectedDataTypeLinked": False,
                            "NSPrivacyCollectedDataTypeTracking": False,
                            "NSPrivacyCollectedDataTypePurposes": ["Analytics"],
                        }
                    ],
                },
            ),
            (
                "SDK/PrivacyInfo.xcprivacy",
                {
                    "NSPrivacyCollectedDataTypes": [
                        {
                            "NSPrivacyCollectedDataType": "DeviceID",
                            "NSPrivacyCollectedDataTypeLinked": True,
                            "NSPrivacyCollectedDataTypeTracking": True,
                            "NSPrivacyCollectedDataTypePurposes": ["Advertising"],
                        }
                    ],
                },
            ),
        ]

        result = aggregate(manifests)

        self.assertTrue(result["any_data_type_tracking"])
        self.assertEqual(
            result["collected_data_types"]["DeviceID"],
            {
                "linked": True,
                "tracking": True,
                "purposes": ["Advertising", "Analytics"],
            },
        )

    def test_loads_manifest_from_app_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Example.app"
            app.mkdir()
            manifest = app / "PrivacyInfo.xcprivacy"
            manifest.write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))

            loaded = load_manifests(app)

            self.assertEqual(loaded, [("PrivacyInfo.xcprivacy", {"NSPrivacyTracking": False})])


if __name__ == "__main__":
    unittest.main()
