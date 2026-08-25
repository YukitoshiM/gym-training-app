import base64
import sqlite3
import tempfile
import unittest
from pathlib import Path

from apple_identity import AppleRefreshTokenStore, AppleTokenStorageError


class AppleRefreshTokenStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database_path = Path(self.temporary_directory.name) / "apple-tokens.sqlite3"
        self.encryption_key = base64.urlsafe_b64encode(b"a" * 32).decode("ascii").rstrip("=")
        self.store = AppleRefreshTokenStore(self.database_path, self.encryption_key)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_tokens_are_encrypted_idempotent_and_deletable(self) -> None:
        account_key = "account-1"
        refresh_token = "sensitive-apple-refresh-token"
        self.store.add(account_key, refresh_token)
        self.store.add(account_key, refresh_token)

        with sqlite3.connect(self.database_path) as connection:
            rows = connection.execute(
                "SELECT encrypted_token FROM apple_refresh_tokens"
            ).fetchall()
        self.assertEqual(len(rows), 1)
        self.assertNotIn(refresh_token.encode("utf-8"), bytes(rows[0][0]))

        tokens = self.store.tokens(account_key)
        self.assertEqual([value for _, value in tokens], [refresh_token])
        self.store.delete(tokens[0][0])
        self.assertEqual(self.store.tokens(account_key), [])

    def test_account_key_is_bound_as_authenticated_encryption_context(self) -> None:
        self.store.add("account-1", "refresh-token")
        with sqlite3.connect(self.database_path) as connection:
            connection.execute(
                "UPDATE apple_refresh_tokens SET account_key = ?",
                ("account-2",),
            )
        with self.assertRaises(AppleTokenStorageError):
            self.store.tokens("account-2")

    def test_invalid_or_missing_key_does_not_open_store(self) -> None:
        unconfigured = AppleRefreshTokenStore(self.database_path, "")
        self.assertFalse(unconfigured.is_configured)
        with self.assertRaises(AppleTokenStorageError):
            unconfigured.add("account", "token")

        with self.assertRaises(AppleTokenStorageError):
            AppleRefreshTokenStore(self.database_path, base64.urlsafe_b64encode(b"short").decode())


if __name__ == "__main__":
    unittest.main()
