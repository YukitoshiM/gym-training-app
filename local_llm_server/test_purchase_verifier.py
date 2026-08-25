import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from purchase_verifier import AppStoreCreditPurchaseVerifier, PurchaseVerificationError


class AppStoreCreditPurchaseVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.verifier = AppStoreCreditPurchaseVerifier()
        self.verifier.root_certificates = [b"test-root"]

    def test_purchase_requires_known_product_account_and_active_transaction(self) -> None:
        decoded = SimpleNamespace(
            productId="com.yukitoshim.gymtrainingapp.credits50",
            transactionId="transaction-1",
            appAccountToken="account-token",
            revocationDate=None,
            quantity=1,
        )
        apple = MagicMock()
        apple.verify_and_decode_signed_transaction.return_value = decoded

        with patch("purchase_verifier.SignedDataVerifier", return_value=apple):
            purchase = self.verifier.verify("signed", "account-token")

        self.assertEqual(purchase.transaction_id, "transaction-1")
        self.assertEqual(purchase.credits, 50)

        decoded.appAccountToken = "another-account"
        with (
            patch("purchase_verifier.SignedDataVerifier", return_value=apple),
            self.assertRaises(PurchaseVerificationError),
        ):
            self.verifier.verify("signed", "account-token")

    def test_refund_notification_verifies_nested_transaction(self) -> None:
        notification = SimpleNamespace(
            rawNotificationType="REFUND",
            notificationType=None,
            notificationUUID="notification-1",
            data=SimpleNamespace(signedTransactionInfo="nested-transaction"),
        )
        decoded = SimpleNamespace(
            productId="com.yukitoshim.gymtrainingapp.credits150",
            transactionId="transaction-150",
        )
        apple = MagicMock()
        apple.verify_and_decode_notification.return_value = notification
        apple.verify_and_decode_signed_transaction.return_value = decoded

        with patch("purchase_verifier.SignedDataVerifier", return_value=apple):
            refund = self.verifier.verify_refund_notification("signed-notification")

        self.assertIsNotNone(refund)
        self.assertEqual(refund.transaction_id, "transaction-150")
        self.assertEqual(refund.credits, 150)

    def test_unrelated_notification_is_acknowledged_without_adjustment(self) -> None:
        notification = SimpleNamespace(
            rawNotificationType="TEST",
            notificationType=None,
            notificationUUID="notification-test",
            data=None,
        )
        apple = MagicMock()
        apple.verify_and_decode_notification.return_value = notification

        with patch("purchase_verifier.SignedDataVerifier", return_value=apple):
            self.assertIsNone(self.verifier.verify_refund_notification("signed-notification"))


if __name__ == "__main__":
    unittest.main()
