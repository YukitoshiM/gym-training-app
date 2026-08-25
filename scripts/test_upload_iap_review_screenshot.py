import tempfile
import unittest
from pathlib import Path

from upload_iap_review_screenshot import checksum, create_payload


class UploadIAPReviewScreenshotTests(unittest.TestCase):
    def test_create_payload_uses_v2_product_relationship(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            screenshot = Path(directory) / "review.png"
            screenshot.write_bytes(b"image")
            payload = create_payload("iap-123", screenshot)

        self.assertEqual(payload["data"]["type"], "inAppPurchaseAppStoreReviewScreenshots")
        self.assertEqual(payload["data"]["attributes"]["fileName"], "review.png")
        self.assertEqual(payload["data"]["attributes"]["fileSize"], 5)
        self.assertEqual(
            payload["data"]["relationships"]["inAppPurchaseV2"]["data"],
            {"type": "inAppPurchases", "id": "iap-123"},
        )

    def test_checksum_is_lowercase_md5(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            screenshot = Path(directory) / "review.png"
            screenshot.write_bytes(b"image")
            self.assertEqual(checksum(screenshot), "78805a221a988e79ef3f42d7c5bfd418")


if __name__ == "__main__":
    unittest.main()
