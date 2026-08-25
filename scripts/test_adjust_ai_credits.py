import argparse
import unittest

from adjust_ai_credits import normalized_payload


class AdjustAICreditsTests(unittest.TestCase):
    def test_normalizes_valid_payload(self) -> None:
        payload = normalized_payload(argparse.Namespace(
            support_id="ABCDEF0123456789",
            amount=25,
            reason="purchase_missing",
            adjustment_id="01234567-89AB-4DEF-8123-456789ABCDEF",
        ))
        self.assertEqual(payload["support_id"], "abcdef0123456789")
        self.assertEqual(payload["amount"], 25)
        self.assertEqual(payload["adjustment_id"], "01234567-89ab-4def-8123-456789abcdef")

    def test_rejects_invalid_support_id_and_amount(self) -> None:
        base = dict(
            support_id="bad",
            amount=25,
            reason="other",
            adjustment_id="01234567-89ab-4def-8123-456789abcdef",
        )
        with self.assertRaises(ValueError):
            normalized_payload(argparse.Namespace(**base))
        with self.assertRaises(ValueError):
            normalized_payload(argparse.Namespace(**{**base, "support_id": "a" * 16, "amount": 501}))


if __name__ == "__main__":
    unittest.main()
