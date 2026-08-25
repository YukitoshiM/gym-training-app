from __future__ import annotations

import hashlib
import hmac
import base64
import os
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path

import httpx
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

try:
    import jwt
except ImportError:  # pragma: no cover - exercised by deployment preflight
    jwt = None


APPLE_ISSUER = "https://appleid.apple.com"
APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"


@dataclass(frozen=True)
class VerifiedAppleIdentity:
    subject: str


@dataclass(frozen=True)
class AppleTokenExchangeResult:
    refresh_token: str
    identity_token: str


class AppleIdentityVerificationError(Exception):
    pass


class AppleTokenExchangeError(Exception):
    pass


class AppleTokenStorageError(Exception):
    pass


class AppleIdentityVerifier:
    def __init__(self, audience: str) -> None:
        self.audience = audience.strip()
        self._key_client = jwt.PyJWKClient(APPLE_KEYS_URL, cache_jwk_set=True) if jwt else None

    @property
    def is_configured(self) -> bool:
        return bool(self.audience and self._key_client is not None)

    def verify(self, identity_token: str, raw_nonce: str) -> VerifiedAppleIdentity:
        if not self.is_configured:
            raise AppleIdentityVerificationError("Sign in with Apple is not configured")
        expected_nonce = hashlib.sha256(raw_nonce.encode("utf-8")).hexdigest()
        try:
            signing_key = self._key_client.get_signing_key_from_jwt(identity_token)
            payload = jwt.decode(
                identity_token,
                signing_key.key,
                algorithms=["RS256"],
                audience=self.audience,
                issuer=APPLE_ISSUER,
                options={"require": ["exp", "iss", "aud", "sub", "nonce"]},
            )
        except Exception as error:
            raise AppleIdentityVerificationError("Apple identity token is invalid") from error
        token_nonce = str(payload.get("nonce", ""))
        if not hmac.compare_digest(token_nonce, expected_nonce):
            raise AppleIdentityVerificationError("Apple identity nonce is invalid")
        subject = str(payload.get("sub", "")).strip()
        if not subject:
            raise AppleIdentityVerificationError("Apple identity subject is missing")
        return VerifiedAppleIdentity(subject=subject)

    def verify_exchanged_identity(self, identity_token: str) -> VerifiedAppleIdentity:
        if not self.is_configured:
            raise AppleIdentityVerificationError("Sign in with Apple is not configured")
        try:
            signing_key = self._key_client.get_signing_key_from_jwt(identity_token)
            payload = jwt.decode(
                identity_token,
                signing_key.key,
                algorithms=["RS256"],
                audience=self.audience,
                issuer=APPLE_ISSUER,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
        except Exception as error:
            raise AppleIdentityVerificationError("Exchanged Apple identity token is invalid") from error
        subject = str(payload.get("sub", "")).strip()
        if not subject:
            raise AppleIdentityVerificationError("Exchanged Apple identity subject is missing")
        return VerifiedAppleIdentity(subject=subject)


class AppleTokenClient:
    token_url = "https://appleid.apple.com/auth/token"
    revoke_url = "https://appleid.apple.com/auth/revoke"

    def __init__(
        self,
        *,
        client_id: str,
        team_id: str,
        key_id: str,
        private_key_path: str,
    ) -> None:
        self.client_id = client_id.strip()
        self.team_id = team_id.strip()
        self.key_id = key_id.strip()
        self.private_key_path = Path(private_key_path).expanduser() if private_key_path.strip() else None

    @classmethod
    def from_environment(cls, default_client_id: str) -> "AppleTokenClient":
        return cls(
            client_id=os.getenv("APPLE_CLIENT_ID", default_client_id),
            team_id=os.getenv("APPLE_TEAM_ID", ""),
            key_id=os.getenv("APPLE_KEY_ID", ""),
            private_key_path=os.getenv("APPLE_PRIVATE_KEY_PATH", ""),
        )

    @property
    def is_configured(self) -> bool:
        return bool(
            jwt
            and self.client_id
            and self.team_id
            and self.key_id
            and self.private_key_path
            and self.private_key_path.is_file()
        )

    def _client_secret(self) -> str:
        if not self.is_configured:
            raise AppleTokenExchangeError("Apple token exchange is not configured")
        now = int(time.time())
        try:
            private_key = self.private_key_path.read_text(encoding="utf-8")
            return jwt.encode(
                {
                    "iss": self.team_id,
                    "iat": now,
                    "exp": now + 300,
                    "aud": APPLE_ISSUER,
                    "sub": self.client_id,
                },
                private_key,
                algorithm="ES256",
                headers={"kid": self.key_id},
            )
        except Exception as error:
            raise AppleTokenExchangeError("Apple client secret could not be generated") from error

    async def exchange_authorization_code(self, authorization_code: str) -> AppleTokenExchangeResult:
        payload = {
            "client_id": self.client_id,
            "client_secret": self._client_secret(),
            "code": authorization_code,
            "grant_type": "authorization_code",
        }
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.post(self.token_url, data=payload)
            response.raise_for_status()
            response_payload = response.json()
            refresh_token = str(response_payload.get("refresh_token", "")).strip()
            identity_token = str(response_payload.get("id_token", "")).strip()
        except Exception as error:
            raise AppleTokenExchangeError("Apple authorization code exchange failed") from error
        if not refresh_token or not identity_token:
            raise AppleTokenExchangeError("Apple did not return the required account tokens")
        return AppleTokenExchangeResult(refresh_token=refresh_token, identity_token=identity_token)

    async def revoke_refresh_token(self, refresh_token: str) -> None:
        payload = {
            "client_id": self.client_id,
            "client_secret": self._client_secret(),
            "token": refresh_token,
            "token_type_hint": "refresh_token",
        }
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.post(self.revoke_url, data=payload)
            response.raise_for_status()
        except Exception as error:
            raise AppleTokenExchangeError("Apple token revocation failed") from error


class AppleRefreshTokenStore:
    def __init__(self, path: Path, encryption_key: str) -> None:
        self.path = path.expanduser()
        self._key = self._decode_key(encryption_key)
        if self._key is not None:
            self._prepare_database()

    @classmethod
    def from_environment(cls) -> "AppleRefreshTokenStore":
        path = Path(
            os.getenv(
                "AI_APPLE_TOKEN_DB_PATH",
                str(Path.home() / "Library/Application Support/BodyMode/apple-tokens.sqlite3"),
            )
        )
        return cls(path, os.getenv("AI_APPLE_TOKEN_ENCRYPTION_KEY", ""))

    @property
    def is_configured(self) -> bool:
        return self._key is not None

    def add(self, account_key: str, refresh_token: str) -> None:
        if not self.is_configured:
            raise AppleTokenStorageError("Apple refresh token encryption is not configured")
        token_hash = hashlib.sha256(refresh_token.encode("utf-8")).hexdigest()
        nonce = os.urandom(12)
        encrypted = nonce + AESGCM(self._key).encrypt(
            nonce,
            refresh_token.encode("utf-8"),
            account_key.encode("utf-8"),
        )
        with self._connection() as connection:
            connection.execute(
                """
                INSERT OR IGNORE INTO apple_refresh_tokens(
                    account_key, token_hash, encrypted_token, created_at
                ) VALUES (?, ?, ?, ?)
                """,
                (account_key, token_hash, encrypted, int(time.time())),
            )

    def tokens(self, account_key: str) -> list[tuple[int, str]]:
        if not self.is_configured:
            raise AppleTokenStorageError("Apple refresh token encryption is not configured")
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT id, encrypted_token FROM apple_refresh_tokens WHERE account_key = ? ORDER BY id",
                (account_key,),
            ).fetchall()
        result: list[tuple[int, str]] = []
        for token_id, encrypted in rows:
            try:
                value = bytes(encrypted)
                token = AESGCM(self._key).decrypt(
                    value[:12],
                    value[12:],
                    account_key.encode("utf-8"),
                ).decode("utf-8")
            except Exception as error:
                raise AppleTokenStorageError("Stored Apple refresh token could not be decrypted") from error
            result.append((int(token_id), token))
        return result

    def delete(self, token_id: int) -> None:
        if not self.is_configured:
            raise AppleTokenStorageError("Apple refresh token encryption is not configured")
        with self._connection() as connection:
            connection.execute("DELETE FROM apple_refresh_tokens WHERE id = ?", (int(token_id),))

    @staticmethod
    def _decode_key(value: str) -> bytes | None:
        normalized = value.strip()
        if not normalized:
            return None
        try:
            padded = normalized + "=" * (-len(normalized) % 4)
            key = base64.urlsafe_b64decode(padded.encode("ascii"))
        except Exception as error:
            raise AppleTokenStorageError("Apple token encryption key is invalid") from error
        if len(key) != 32:
            raise AppleTokenStorageError("Apple token encryption key must decode to 32 bytes")
        return key

    def _prepare_database(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS apple_refresh_tokens(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_key TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE,
                    encrypted_token BLOB NOT NULL,
                    created_at INTEGER NOT NULL
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_apple_refresh_tokens_account ON apple_refresh_tokens(account_key)"
            )
        try:
            self.path.chmod(0o600)
        except OSError:
            pass

    def _connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.execute("PRAGMA foreign_keys = ON")
        return connection
