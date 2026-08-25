import tempfile
import unittest
from pathlib import Path

from credit_ledger import (
    AICreditLedger,
    CreditRequestConflict,
    InsufficientCredits,
)


class AICreditLedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database_path = Path(self.temporary_directory.name) / "credits.sqlite3"
        self.ledger = AICreditLedger(
            self.database_path,
            feature_costs={"chat": 1, "meal": 3, "body_photo": 4},
            signup_bonus=20,
            pending_ttl_seconds=60,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_signup_bonus_is_granted_once_and_survives_restart(self) -> None:
        first, balance = self.ledger.claim_signup_bonus("account-1", now=1_700_000_000)
        second, repeated_balance = self.ledger.claim_signup_bonus("account-1", now=1_700_000_001)

        restarted = AICreditLedger(
            self.database_path,
            feature_costs={"chat": 1, "meal": 3, "body_photo": 4},
            signup_bonus=20,
        )

        self.assertTrue(first)
        self.assertFalse(second)
        self.assertEqual(balance.available, 20)
        self.assertEqual(repeated_balance.available, 20)
        self.assertEqual(restarted.balance("account-1").available, 20)

    def test_successful_ai_request_consumes_feature_cost(self) -> None:
        self.ledger.claim_signup_bonus("account-1")
        reservation = self.ledger.reserve(
            account_key="account-1",
            feature="meal",
            request_id="request-1",
        )

        completed = self.ledger.complete("request-1")

        self.assertEqual(reservation.cost, 3)
        self.assertEqual(reservation.balance.available, 17)
        self.assertEqual(reservation.balance.reserved, 3)
        self.assertEqual(completed.available, 17)
        self.assertEqual(completed.reserved, 0)
        self.assertEqual(self.ledger.history("account-1")[0]["amount"], -3)

    def test_failed_ai_request_returns_reserved_credits(self) -> None:
        self.ledger.claim_signup_bonus("account-1")
        self.ledger.reserve(
            account_key="account-1",
            feature="body_photo",
            request_id="request-failed",
        )

        self.assertTrue(self.ledger.release("request-failed"))
        self.assertEqual(self.ledger.balance("account-1").available, 20)
        self.assertEqual(len(self.ledger.history("account-1")), 1)

    def test_concurrent_reservations_cannot_overspend(self) -> None:
        self.ledger.grant(
            account_key="account-1",
            source="admin",
            amount=3,
            transaction_key="admin-1",
        )
        self.ledger.reserve(
            account_key="account-1",
            feature="meal",
            request_id="request-1",
        )

        with self.assertRaises(InsufficientCredits):
            self.ledger.reserve(
                account_key="account-1",
                feature="chat",
                request_id="request-2",
            )

    def test_oldest_promotional_credits_are_consumed_before_purchase(self) -> None:
        self.ledger.grant(
            account_key="account-1",
            source="purchase",
            amount=10,
            transaction_key="purchase-1",
        )
        self.ledger.grant(
            account_key="account-1",
            source="signup",
            amount=2,
            transaction_key="signup:account-1",
        )

        self.ledger.reserve(
            account_key="account-1",
            feature="meal",
            request_id="request-1",
        )
        completed = self.ledger.complete("request-1")

        self.assertEqual(completed.buckets["signup"], 0)
        self.assertEqual(completed.buckets["purchase"], 9)

    def test_transaction_and_request_ids_are_idempotent_or_rejected(self) -> None:
        self.assertTrue(
            self.ledger.grant(
                account_key="account-1",
                source="rewarded_ad",
                amount=5,
                transaction_key="ad-1",
            )
        )
        self.assertFalse(
            self.ledger.grant(
                account_key="account-1",
                source="rewarded_ad",
                amount=5,
                transaction_key="ad-1",
            )
        )
        self.ledger.reserve(
            account_key="account-1",
            feature="chat",
            request_id="request-1",
        )
        with self.assertRaises(CreditRequestConflict):
            self.ledger.reserve(
                account_key="account-1",
                feature="chat",
                request_id="request-1",
            )

    def test_expired_pending_reservation_is_returned(self) -> None:
        self.ledger.grant(
            account_key="account-1",
            source="admin",
            amount=5,
            transaction_key="admin-1",
            now=1_700_000_000,
        )
        self.ledger.reserve(
            account_key="account-1",
            feature="meal",
            request_id="request-expired",
            now=1_700_000_000,
        )

        balance = self.ledger.balance("account-1", now=1_700_000_061)

        self.assertEqual(balance.available, 5)
        self.assertEqual(balance.reserved, 0)

    def test_account_deletion_removes_balance_but_not_signup_claim(self) -> None:
        granted, _ = self.ledger.claim_signup_bonus("account-1")
        self.ledger.grant(
            account_key="account-1",
            source="purchase",
            amount=10,
            transaction_key="purchase-1",
        )

        deleted = self.ledger.delete_account("account-1")
        granted_again, balance = self.ledger.claim_signup_bonus("account-1")

        self.assertTrue(granted)
        self.assertEqual(deleted["removed_credits"], 30)
        self.assertFalse(granted_again)
        self.assertEqual(balance.available, 0)

    def test_rewarded_ad_is_idempotent_and_limited_to_three_per_day(self) -> None:
        for index in range(3):
            granted, _, remaining = self.ledger.claim_rewarded_ad(
                account_key="account-1",
                event_id=f"event-{index:012d}",
                now=1_700_000_000,
            )
            self.assertTrue(granted)
            self.assertEqual(remaining, 2 - index)

        granted, balance, remaining = self.ledger.claim_rewarded_ad(
            account_key="account-1",
            event_id="event-over-limit-0000",
            now=1_700_000_000,
        )
        self.assertFalse(granted)
        self.assertEqual(remaining, 0)
        self.assertEqual(balance.available, 15)

        duplicate, duplicate_balance, _ = self.ledger.claim_rewarded_ad(
            account_key="account-1",
            event_id="event-000000000000",
            now=1_700_000_000,
        )
        self.assertFalse(duplicate)
        self.assertEqual(duplicate_balance.available, 15)

    def test_refund_removes_only_unused_purchase_credits(self) -> None:
        granted, credited = self.ledger.grant_purchase(
            account_key="account-1",
            amount=50,
            transaction_key="app_store:purchase-1",
        )

        adjusted, account, removed, debt = self.ledger.refund_purchase(
            transaction_key="app_store:purchase-1",
            amount=50,
        )
        duplicate = self.ledger.refund_purchase(
            transaction_key="app_store:purchase-1",
            amount=50,
        )

        self.assertTrue(granted)
        self.assertEqual(credited, 50)
        self.assertTrue(adjusted)
        self.assertEqual(account, "account-1")
        self.assertEqual(removed, 50)
        self.assertEqual(debt, 0)
        self.assertFalse(duplicate[0])
        self.assertEqual(self.ledger.balance("account-1").available, 0)

    def test_used_refund_is_repaid_from_next_purchase_without_negative_balance(self) -> None:
        self.ledger.grant_purchase(
            account_key="account-1",
            amount=50,
            transaction_key="app_store:purchase-1",
        )
        for index in range(50):
            self.ledger.reserve(
                account_key="account-1",
                feature="chat",
                request_id=f"request-{index}",
            )
            self.ledger.complete(f"request-{index}")

        adjusted = self.ledger.refund_purchase(
            transaction_key="app_store:purchase-1",
            amount=50,
        )
        granted, credited = self.ledger.grant_purchase(
            account_key="account-1",
            amount=50,
            transaction_key="app_store:purchase-2",
        )

        self.assertEqual(adjusted[2:], (0, 50))
        self.assertTrue(granted)
        self.assertEqual(credited, 0)
        self.assertEqual(self.ledger.balance("account-1").available, 0)

    def test_refund_before_purchase_verification_blocks_later_grant(self) -> None:
        adjusted = self.ledger.refund_purchase(
            transaction_key="app_store:purchase-before-verify",
            amount=50,
        )
        granted, credited = self.ledger.grant_purchase(
            account_key="account-1",
            amount=50,
            transaction_key="app_store:purchase-before-verify",
        )

        self.assertTrue(adjusted[0])
        self.assertFalse(granted)
        self.assertEqual(credited, 0)
        self.assertEqual(self.ledger.balance("account-1").available, 0)


if __name__ == "__main__":
    unittest.main()
