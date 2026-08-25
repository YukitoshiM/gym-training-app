from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier


class PurchaseVerificationError(Exception):
    pass


@dataclass(frozen=True)
class VerifiedCreditPurchase:
    transaction_id: str
    product_id: str
    credits: int


@dataclass(frozen=True)
class VerifiedCreditRefund:
    notification_id: str
    transaction_id: str
    product_id: str
    credits: int


class AppStoreCreditPurchaseVerifier:
    def __init__(self) -> None:
        self.bundle_id = os.getenv("APP_STORE_BUNDLE_ID", "com.yukitoshim.gymtrainingapp")
        self.app_apple_id = int(os.getenv("APP_STORE_APPLE_ID", "6799871527"))
        self.product_credits = {
            "com.yukitoshim.gymtrainingapp.credits50": 50,
            "com.yukitoshim.gymtrainingapp.credits150": 150,
            "com.yukitoshim.gymtrainingapp.credits500": 500,
        }
        root_path = Path(os.getenv("APP_STORE_ROOT_CERTIFICATES_PATH", "")).expanduser()
        self.root_certificates = (
            [path.read_bytes() for path in sorted(root_path.glob("*.cer"))]
            if root_path.is_dir()
            else []
        )

    @property
    def is_configured(self) -> bool:
        return bool(self.root_certificates)

    def verify(self, signed_transaction: str, expected_account_token: str) -> VerifiedCreditPurchase:
        if not self.is_configured:
            raise PurchaseVerificationError("App Store verification certificates are not configured")

        decoded = None
        last_error: Exception | None = None
        for environment in (Environment.PRODUCTION, Environment.SANDBOX):
            try:
                verifier = SignedDataVerifier(
                    self.root_certificates,
                    True,
                    environment,
                    self.bundle_id,
                    self.app_apple_id if environment == Environment.PRODUCTION else None,
                )
                decoded = verifier.verify_and_decode_signed_transaction(signed_transaction)
                break
            except Exception as error:  # Library exposes several verification exception types.
                last_error = error
        if decoded is None:
            raise PurchaseVerificationError("Apple transaction signature is invalid") from last_error
        if decoded.productId not in self.product_credits:
            raise PurchaseVerificationError("Unknown credit product")
        if decoded.transactionId is None or decoded.appAccountToken != expected_account_token:
            raise PurchaseVerificationError("Transaction does not belong to this BodyMode account")
        if decoded.revocationDate is not None or (decoded.quantity or 1) != 1:
            raise PurchaseVerificationError("Transaction is revoked or has an invalid quantity")
        return VerifiedCreditPurchase(
            transaction_id=decoded.transactionId,
            product_id=decoded.productId,
            credits=self.product_credits[decoded.productId],
        )

    def verify_refund_notification(self, signed_payload: str) -> VerifiedCreditRefund | None:
        if not self.is_configured:
            raise PurchaseVerificationError("App Store verification certificates are not configured")
        notification = None
        verifier = None
        last_error: Exception | None = None
        for environment in (Environment.PRODUCTION, Environment.SANDBOX):
            try:
                candidate = SignedDataVerifier(
                    self.root_certificates,
                    True,
                    environment,
                    self.bundle_id,
                    self.app_apple_id if environment == Environment.PRODUCTION else None,
                )
                notification = candidate.verify_and_decode_notification(signed_payload)
                verifier = candidate
                break
            except Exception as error:
                last_error = error
        if notification is None or verifier is None:
            raise PurchaseVerificationError("Apple notification signature is invalid") from last_error
        notification_type = notification.rawNotificationType or (
            notification.notificationType.value if notification.notificationType is not None else ""
        )
        if notification_type not in {"REFUND", "REVOKE"}:
            return None
        signed_transaction = notification.data.signedTransactionInfo if notification.data else None
        if not signed_transaction:
            raise PurchaseVerificationError("Refund notification has no transaction")
        try:
            decoded = verifier.verify_and_decode_signed_transaction(signed_transaction)
        except Exception as error:
            raise PurchaseVerificationError("Refund transaction signature is invalid") from error
        if decoded.productId not in self.product_credits or decoded.transactionId is None:
            raise PurchaseVerificationError("Refund does not reference a credit product")
        if not notification.notificationUUID:
            raise PurchaseVerificationError("Refund notification has no identifier")
        return VerifiedCreditRefund(
            notification_id=notification.notificationUUID,
            transaction_id=decoded.transactionId,
            product_id=decoded.productId,
            credits=self.product_credits[decoded.productId],
        )
