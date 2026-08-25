import base64
import tempfile
import time
import unittest
from pathlib import Path
from urllib.parse import quote_plus

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from rewarded_ad_ssv import (
    GoogleRewardedAdVerifier,
    RewardedAdChallengeStore,
    RewardedAdVerificationError,
)


class GoogleRewardedAdVerifierTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.private_key = ec.generate_private_key(ec.SECP256R1())
        public_pem = self.private_key.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        self.verifier = GoogleRewardedAdVerifier("ca-app-pub-test/rewarded")
        self.verifier._keys = {123: public_pem}
        self.verifier._keys_loaded_at = int(time.time())

    def signed_query(self, *, challenge_id: str = "challenge-123", amount: int = 1) -> bytes:
        signed = "&".join(
            [
                "ad_network=5450213213286189855",
                f"ad_unit={quote_plus('ca-app-pub-test/rewarded')}",
                f"custom_data={quote_plus(challenge_id)}",
                f"reward_amount={amount}",
                "reward_item=credit",
                f"timestamp={int(time.time() * 1000)}",
                "transaction_id=transaction-123",
            ]
        )
        signature = self.private_key.sign(signed.encode("utf-8"), ec.ECDSA(hashes.SHA256()))
        encoded_signature = base64.urlsafe_b64encode(signature).decode("ascii").rstrip("=")
        return f"{signed}&signature={encoded_signature}&key_id=123".encode("utf-8")

    async def test_valid_signature_returns_bounded_reward_event(self) -> None:
        event = await self.verifier.verify(self.signed_query())
        self.assertEqual(event.challenge_id, "challenge-123")
        self.assertEqual(event.transaction_id, "transaction-123")
        self.assertEqual(event.ad_unit_id, "ca-app-pub-test/rewarded")

    async def test_tampered_reward_is_rejected(self) -> None:
        query = self.signed_query().replace(b"reward_amount=1", b"reward_amount=99")
        with self.assertRaises(RewardedAdVerificationError):
            await self.verifier.verify(query)


class RewardedAdChallengeStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.store = RewardedAdChallengeStore(
            Path(self.temporary_directory.name) / "rewarded.sqlite3",
            lifetime_seconds=60,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_challenge_is_account_bound_and_transaction_is_single_use(self) -> None:
        first = self.store.create("account-1", now=100)
        verified, is_new = self.store.verify_event(first.challenge_id, "transaction-1", now=110)
        self.assertTrue(is_new)
        self.assertTrue(verified.verified)
        self.store.save_result(first.challenge_id, True, 2)
        self.assertTrue(self.store.status(first.challenge_id, "account-1").granted)

        with self.assertRaises(RewardedAdVerificationError):
            self.store.status(first.challenge_id, "account-2")

        second = self.store.create("account-1", now=100)
        with self.assertRaises(RewardedAdVerificationError):
            self.store.verify_event(second.challenge_id, "transaction-1", now=110)

    def test_expired_challenge_is_rejected(self) -> None:
        challenge = self.store.create("account-1", now=100)
        with self.assertRaises(RewardedAdVerificationError):
            self.store.verify_event(challenge.challenge_id, "transaction-1", now=161)


if __name__ == "__main__":
    unittest.main()
