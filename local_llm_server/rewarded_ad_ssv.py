from __future__ import annotations

import base64
import os
import sqlite3
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import parse_qsl

import httpx
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


GOOGLE_REWARDED_KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json"


class RewardedAdVerificationError(Exception):
    pass


@dataclass(frozen=True)
class RewardedAdEvent:
    challenge_id: str
    transaction_id: str
    ad_unit_id: str
    reward_amount: int
    reward_item: str
    timestamp_ms: int


@dataclass(frozen=True)
class RewardedAdChallenge:
    challenge_id: str
    account_key: str
    expires_at: int
    verified: bool
    transaction_id: str | None
    granted: bool | None
    remaining_today: int | None


class GoogleRewardedAdVerifier:
    def __init__(self, expected_ad_unit_id: str, key_cache_seconds: int = 86_400) -> None:
        self.expected_ad_unit_id = expected_ad_unit_id.strip()
        self.key_cache_seconds = max(300, int(key_cache_seconds))
        self._keys: dict[int, bytes] = {}
        self._keys_loaded_at = 0

    @classmethod
    def from_environment(cls) -> "GoogleRewardedAdVerifier":
        return cls(os.getenv("ADMOB_REWARDED_AD_UNIT_ID", ""))

    @property
    def is_configured(self) -> bool:
        return bool(self.expected_ad_unit_id)

    async def verify(self, raw_query: bytes) -> RewardedAdEvent:
        if not self.is_configured:
            raise RewardedAdVerificationError("AdMob rewarded SSV is not configured")
        raw_text = raw_query.decode("utf-8", errors="strict")
        components = raw_text.split("&") if raw_text else []
        signed_components = [
            component
            for component in components
            if not component.startswith("signature=") and not component.startswith("key_id=")
        ]
        parameters = dict(parse_qsl(raw_text, keep_blank_values=True))
        try:
            signature = self._decode_signature(parameters["signature"])
            key_id = int(parameters["key_id"])
            challenge_id = parameters["custom_data"]
            transaction_id = parameters["transaction_id"]
            ad_unit_id = parameters["ad_unit"]
            reward_amount = int(parameters["reward_amount"])
            reward_item = parameters["reward_item"]
            timestamp_ms = int(parameters["timestamp"])
        except (KeyError, TypeError, ValueError) as error:
            raise RewardedAdVerificationError("AdMob SSV parameters are invalid") from error
        if ad_unit_id != self.expected_ad_unit_id:
            raise RewardedAdVerificationError("AdMob rewarded ad unit does not match")
        if reward_amount <= 0 or not challenge_id or not transaction_id:
            raise RewardedAdVerificationError("AdMob reward details are invalid")
        if abs(int(time.time() * 1000) - timestamp_ms) > 24 * 60 * 60 * 1000:
            raise RewardedAdVerificationError("AdMob SSV timestamp is outside the accepted window")

        public_key = await self._public_key(key_id)
        signed_data = "&".join(signed_components).encode("utf-8")
        try:
            public_key.verify(signature, signed_data, ec.ECDSA(hashes.SHA256()))
        except InvalidSignature as error:
            raise RewardedAdVerificationError("AdMob SSV signature is invalid") from error
        return RewardedAdEvent(
            challenge_id=challenge_id,
            transaction_id=transaction_id,
            ad_unit_id=ad_unit_id,
            reward_amount=reward_amount,
            reward_item=reward_item,
            timestamp_ms=timestamp_ms,
        )

    async def _public_key(self, key_id: int):
        now = int(time.time())
        if not self._keys or now - self._keys_loaded_at >= self.key_cache_seconds:
            await self._refresh_keys()
        pem = self._keys.get(key_id)
        if pem is None:
            await self._refresh_keys()
            pem = self._keys.get(key_id)
        if pem is None:
            raise RewardedAdVerificationError("AdMob SSV key is unknown")
        try:
            key = serialization.load_pem_public_key(pem)
        except Exception as error:
            raise RewardedAdVerificationError("AdMob SSV public key is invalid") from error
        if not isinstance(key, ec.EllipticCurvePublicKey):
            raise RewardedAdVerificationError("AdMob SSV public key type is invalid")
        return key

    async def _refresh_keys(self) -> None:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(GOOGLE_REWARDED_KEYS_URL)
            response.raise_for_status()
            payload = response.json()
            keys = {
                int(item["keyId"]): str(item["pem"]).encode("utf-8")
                for item in payload.get("keys", [])
                if "keyId" in item and "pem" in item
            }
        except Exception as error:
            raise RewardedAdVerificationError("AdMob SSV keys could not be loaded") from error
        if not keys:
            raise RewardedAdVerificationError("AdMob SSV key set is empty")
        self._keys = keys
        self._keys_loaded_at = int(time.time())

    @staticmethod
    def _decode_signature(value: str) -> bytes:
        try:
            padded = value + "=" * (-len(value) % 4)
            return base64.urlsafe_b64decode(padded.encode("ascii"))
        except Exception as error:
            raise RewardedAdVerificationError("AdMob SSV signature encoding is invalid") from error


class RewardedAdChallengeStore:
    def __init__(self, path: Path, lifetime_seconds: int = 900) -> None:
        self.path = path.expanduser()
        self.lifetime_seconds = max(60, int(lifetime_seconds))
        self._prepare_database()

    @classmethod
    def from_environment(cls) -> "RewardedAdChallengeStore":
        path = Path(
            os.getenv(
                "AI_REWARDED_AD_DB_PATH",
                str(Path.home() / "Library/Application Support/BodyMode/rewarded-ads.sqlite3"),
            )
        )
        return cls(path)

    def create(self, account_key: str, now: int | None = None) -> RewardedAdChallenge:
        timestamp = int(time.time()) if now is None else int(now)
        challenge_id = str(uuid.uuid4()).lower()
        expires_at = timestamp + self.lifetime_seconds
        with self._connection() as connection:
            connection.execute(
                "INSERT INTO rewarded_ad_challenges(challenge_id, account_key, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (challenge_id, account_key, timestamp, expires_at),
            )
        return RewardedAdChallenge(challenge_id, account_key, expires_at, False, None, None, None)

    def verify_event(
        self,
        challenge_id: str,
        transaction_id: str,
        now: int | None = None,
    ) -> tuple[RewardedAdChallenge, bool]:
        timestamp = int(time.time()) if now is None else int(now)
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT account_key, expires_at, transaction_id, granted, remaining_today FROM rewarded_ad_challenges WHERE challenge_id = ?",
                (challenge_id,),
            ).fetchone()
            if row is None:
                raise RewardedAdVerificationError("Rewarded ad challenge was not found")
            account_key, expires_at, existing_transaction, granted, remaining = row
            if timestamp > int(expires_at):
                raise RewardedAdVerificationError("Rewarded ad challenge expired")
            if existing_transaction is not None:
                if str(existing_transaction) != transaction_id:
                    raise RewardedAdVerificationError("Rewarded ad challenge was already used")
                connection.commit()
                return self._record(challenge_id, connection), False
            transaction_owner = connection.execute(
                "SELECT challenge_id FROM rewarded_ad_challenges WHERE transaction_id = ?",
                (transaction_id,),
            ).fetchone()
            if transaction_owner is not None:
                raise RewardedAdVerificationError("Rewarded ad transaction was already used")
            connection.execute(
                "UPDATE rewarded_ad_challenges SET verified_at = ?, transaction_id = ? WHERE challenge_id = ?",
                (timestamp, transaction_id, challenge_id),
            )
            connection.commit()
            return self.status(challenge_id, str(account_key)), True

    def save_result(self, challenge_id: str, granted: bool, remaining_today: int) -> None:
        with self._connection() as connection:
            connection.execute(
                "UPDATE rewarded_ad_challenges SET granted = ?, remaining_today = ? WHERE challenge_id = ?",
                (1 if granted else 0, int(remaining_today), challenge_id),
            )

    def status(self, challenge_id: str, account_key: str) -> RewardedAdChallenge:
        with self._connection() as connection:
            record = self._record(challenge_id, connection)
        if record.account_key != account_key:
            raise RewardedAdVerificationError("Rewarded ad challenge belongs to another account")
        return record

    def _record(self, challenge_id: str, connection: sqlite3.Connection) -> RewardedAdChallenge:
        row = connection.execute(
            "SELECT account_key, expires_at, verified_at, transaction_id, granted, remaining_today FROM rewarded_ad_challenges WHERE challenge_id = ?",
            (challenge_id,),
        ).fetchone()
        if row is None:
            raise RewardedAdVerificationError("Rewarded ad challenge was not found")
        account_key, expires_at, verified_at, transaction_id, granted, remaining = row
        return RewardedAdChallenge(
            challenge_id=challenge_id,
            account_key=str(account_key),
            expires_at=int(expires_at),
            verified=verified_at is not None,
            transaction_id=str(transaction_id) if transaction_id is not None else None,
            granted=None if granted is None else bool(granted),
            remaining_today=None if remaining is None else int(remaining),
        )

    def _prepare_database(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS rewarded_ad_challenges(
                    challenge_id TEXT PRIMARY KEY,
                    account_key TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    verified_at INTEGER,
                    transaction_id TEXT UNIQUE,
                    granted INTEGER,
                    remaining_today INTEGER
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_rewarded_ad_challenges_account ON rewarded_ad_challenges(account_key, created_at)"
            )

    def _connection(self) -> sqlite3.Connection:
        return sqlite3.connect(self.path, timeout=10)
