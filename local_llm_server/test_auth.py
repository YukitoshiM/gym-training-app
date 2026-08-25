import hashlib
import base64
import importlib
import asyncio
import json
import os
import sys
import tempfile
import unittest
import uuid
import time
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient


class AuthenticationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        enrollment_key = "family-test-enrollment-key"
        owner_key = "owner-test-enrollment-key"
        enrollment_hash = hashlib.sha256(enrollment_key.encode("utf-8")).hexdigest()
        owner_hash = hashlib.sha256(owner_key.encode("utf-8")).hexdigest()
        enrollment_file = root / "enrollment_keys.json"
        enrollment_file.write_text(
            json.dumps({
                "family-test": f"sha256:{enrollment_hash}",
                "owner": f"sha256:{owner_hash}",
            }),
            encoding="utf-8",
        )
        os.environ.update(
            {
                "LOCAL_AI_API_KEY": "legacy-disabled-for-test",
                "AI_RUNTIME_ENVIRONMENT": "test",
                "AI_AUTH_MODE": "token_required",
                "AI_TOKEN_SIGNING_SECRET": "test-signing-secret-with-more-than-32-characters",
                "AI_TOKEN_TTL_SECONDS": "3600",
                "AI_RATE_LIMIT_PER_MINUTE": "30",
                "AI_TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE": "8",
                "AI_TOKEN_FAILURE_DELAY_SECONDS": "0",
                "AI_ENROLLMENT_KEYS_FILE": str(enrollment_file),
                "AI_AUTH_STATE_PATH": str(root / "auth-state.json"),
                "AI_USAGE_DB_PATH": str(root / "usage.sqlite3"),
                "AI_CREDIT_DB_PATH": str(root / "credits.sqlite3"),
                "AI_APPLE_TOKEN_DB_PATH": str(root / "apple-tokens.sqlite3"),
                "AI_APPLE_TOKEN_ENCRYPTION_KEY": base64.urlsafe_b64encode(b"k" * 32).decode("ascii").rstrip("="),
                "AI_REWARDED_AD_DB_PATH": str(root / "rewarded-ads.sqlite3"),
                "ADMOB_REWARDED_AD_UNIT_ID": "ca-app-pub-test/rewarded",
                "AI_CREDIT_ENFORCEMENT": "1",
                "AI_CREDIT_ACCOUNT_SUBJECT_PREFIXES": "apple:",
                "USAGE_ANALYTICS_DB_PATH": str(root / "usage-analytics.sqlite3"),
                "AI_QUOTA_ENFORCEMENT": "1",
                "AI_QUOTA_EXEMPT_SUBJECTS": "owner",
                "EVIDENCE_RAG_ENABLED": "1",
                "EVIDENCE_RAG_DB_PATH": str(root / "evidence.sqlite3"),
            }
        )
        sys.modules.pop("main", None)
        sys.modules.pop("usage_quota", None)
        self.server = importlib.import_module("main")
        self.server.apple_token_client = SimpleNamespace(
            is_configured=True,
            exchange_authorization_code=AsyncMock(
                return_value=SimpleNamespace(
                    refresh_token="test-refresh-token",
                    identity_token="test-exchanged-identity-token",
                )
            ),
            revoke_refresh_token=AsyncMock(return_value=None),
        )
        self.client = TestClient(self.server.app)
        self.enrollment_key = enrollment_key
        self.owner_key = owner_key

    def issue_apple_account_token(self, apple_subject: str = "apple-user-1") -> tuple[str, dict]:
        identity = self.server.VerifiedAppleIdentity(subject=apple_subject)
        with (
            patch.object(self.server.apple_identity_verifier, "verify", return_value=identity),
            patch.object(
                self.server.apple_identity_verifier,
                "verify_exchanged_identity",
                return_value=identity,
            ),
        ):
            response = self.client.post(
                "/v1/account/apple",
                json={
                    "identity_token": "x" * 128,
                    "authorization_code": "test-authorization-code",
                    "raw_nonce": "test-raw-nonce-1234567890",
                    "installation_id": "00000000-0000-4000-8000-000000000010",
                    "app_version": "1.0",
                },
            )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["access_token"], response.json()

    def tearDown(self) -> None:
        self.client.close()
        self.temporary_directory.cleanup()

    def issue_token(self) -> str:
        response = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": f"Bearer {self.enrollment_key}"},
            json={"installation_id": "00000000-0000-4000-8000-000000000001", "app_version": "1.0"},
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["access_token"]

    def issue_owner_token(self) -> str:
        response = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": f"Bearer {self.owner_key}"},
            json={"installation_id": "00000000-0000-4000-8000-000000000002", "app_version": "1.0"},
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["access_token"]

    def test_ai_failure_reason_uses_only_bounded_operational_codes(self) -> None:
        self.assertEqual(
            self.server._ai_failure_reason(
                self.server.HTTPException(status_code=503, detail={"code": "server_busy"})
            ),
            "server_busy",
        )
        self.assertEqual(
            self.server._ai_failure_reason(
                self.server.HTTPException(status_code=413, detail="too large")
            ),
            "http_413",
        )
        self.assertEqual(self.server._ai_failure_reason(asyncio.CancelledError()), "cancelled")
        self.assertEqual(self.server._ai_failure_reason(RuntimeError("private detail")), "internal_error")

    def test_token_required_mode_rejects_shared_key_and_accepts_access_token(self) -> None:
        legacy = self.client.get(
            "/v1/coaches",
            headers={"Authorization": "Bearer legacy-disabled-for-test"},
        )
        self.assertEqual(legacy.status_code, 401)

        token = self.issue_token()
        authenticated = self.client.get(
            "/v1/coaches",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(authenticated.status_code, 200, authenticated.text)

    def test_revoked_access_token_is_rejected(self) -> None:
        token = self.issue_token()
        headers = {"Authorization": f"Bearer {token}"}
        revoked = self.client.post("/v1/auth/revoke", headers=headers)
        self.assertEqual(revoked.status_code, 204, revoked.text)
        self.assertEqual(self.client.get("/v1/coaches", headers=headers).status_code, 401)

    def test_apple_account_receives_signup_credits_only_once(self) -> None:
        _, first = self.issue_apple_account_token()
        token, second = self.issue_apple_account_token()

        credits = self.client.get(
            "/v1/credits",
            headers={"Authorization": f"Bearer {token}"},
        )

        self.assertTrue(first["signup_granted"])
        self.assertEqual(first["signup_granted_amount"], 20)
        self.assertFalse(second["signup_granted"])
        self.assertEqual(credits.status_code, 200, credits.text)
        self.assertEqual(credits.json()["balance"]["available"], 20)

    def test_apple_authorization_code_must_match_identity_subject(self) -> None:
        original = self.server.VerifiedAppleIdentity(subject="apple-user-1")
        exchanged = self.server.VerifiedAppleIdentity(subject="another-user")
        with (
            patch.object(self.server.apple_identity_verifier, "verify", return_value=original),
            patch.object(
                self.server.apple_identity_verifier,
                "verify_exchanged_identity",
                return_value=exchanged,
            ),
        ):
            response = self.client.post(
                "/v1/account/apple",
                json={
                    "identity_token": "x" * 128,
                    "authorization_code": "test-authorization-code",
                    "raw_nonce": "test-raw-nonce-1234567890",
                    "installation_id": "00000000-0000-4000-8000-000000000010",
                    "app_version": "1.0",
                },
            )
        self.assertEqual(response.status_code, 503, response.text)
        self.assertEqual(response.json()["detail"]["code"], "apple_token_exchange_failed")

    def test_ai_success_consumes_credit_and_failure_returns_it(self) -> None:
        token, _ = self.issue_apple_account_token()
        headers = {"Authorization": f"Bearer {token}"}
        payload = {
            "coach_id": "body_recomposition",
            "purpose": "chat",
            "message": "次の重量は？",
            "context": {},
            "recent_messages": [],
        }
        success_response = {
            "reply": "少しだけ増やしましょう。",
            "memory_candidates": [],
            "evidence": [],
            "evidence_status": {"state": "unavailable"},
            "evidence_claims": [],
        }
        with patch.object(
            self.server,
            "_agent_chat_impl",
            new=AsyncMock(return_value=success_response),
        ):
            success = self.client.post(
                "/v1/agents/chat",
                headers={**headers, "X-Request-ID": "credit-success"},
                json=payload,
            )
        self.assertEqual(success.status_code, 200, success.text)
        after_success = self.client.get("/v1/credits", headers=headers).json()["balance"]
        self.assertEqual(after_success["available"], 19)

        with patch.object(
            self.server,
            "_agent_chat_impl",
            new=AsyncMock(side_effect=self.server.HTTPException(status_code=503, detail="failed")),
        ):
            failure = self.client.post(
                "/v1/agents/chat",
                headers={**headers, "X-Request-ID": "credit-failure"},
                json=payload,
            )
        self.assertEqual(failure.status_code, 503, failure.text)
        after_failure = self.client.get("/v1/credits", headers=headers).json()["balance"]
        self.assertEqual(after_failure["available"], 19)
        self.assertEqual(after_failure["reserved"], 0)

    def test_chat_input_limits_do_not_block_generated_plan_prompts(self) -> None:
        token, _ = self.issue_apple_account_token()
        headers = {"Authorization": f"Bearer {token}"}

        response = {
            "reply": "計画案です。",
            "memory_candidates": [],
            "evidence": [],
            "evidence_status": {"state": "unavailable"},
            "evidence_claims": [],
        }
        with patch.object(
            self.server,
            "_agent_chat_impl",
            new=AsyncMock(return_value=response),
        ):
            chat = self.client.post(
                "/v1/agents/chat",
                headers=headers,
                json={
                    "coach_id": "hypertrophy",
                    "purpose": "chat",
                    "message": "x" * 301,
                    "context": {},
                    "recent_messages": [],
                },
            )
            plan = self.client.post(
                "/v1/agents/chat",
                headers=headers,
                json={
                    "coach_id": "hypertrophy",
                    "purpose": "plan_generation",
                    "message": "x" * 301,
                    "context": {},
                    "recent_messages": [],
                },
            )

        self.assertEqual(chat.status_code, 422, chat.text)
        self.assertNotEqual(plan.status_code, 422, plan.text)

    def test_agent_context_and_recent_message_limits_are_enforced(self) -> None:
        token, _ = self.issue_apple_account_token()
        headers = {"Authorization": f"Bearer {token}"}

        oversized_context = self.client.post(
            "/v1/agents/chat",
            headers=headers,
            json={
                "coach_id": "hypertrophy",
                "purpose": "chat",
                "message": "相談",
                "context": {"notes": "x" * 24_001},
                "recent_messages": [],
            },
        )
        oversized_recent_message = self.client.post(
            "/v1/agents/chat",
            headers=headers,
            json={
                "coach_id": "hypertrophy",
                "purpose": "chat",
                "message": "相談",
                "context": {},
                "recent_messages": [{"role": "user", "content": "x" * 1_001}],
            },
        )

        self.assertEqual(oversized_context.status_code, 422, oversized_context.text)
        self.assertEqual(oversized_recent_message.status_code, 422, oversized_recent_message.text)

    def test_unregistered_token_cannot_use_ai_when_credits_are_enforced(self) -> None:
        token = self.issue_token()
        response = self.client.post(
            "/v1/agents/chat",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "coach_id": "hypertrophy",
                "purpose": "chat",
                "message": "次回の重量を相談したい",
                "context": {},
                "recent_messages": [],
            },
        )

        self.assertEqual(response.status_code, 403, response.text)
        self.assertEqual(response.json()["detail"]["code"], "account_sign_in_required")

    def test_rewarded_ad_claim_is_limited_and_idempotent(self) -> None:
        token, _ = self.issue_apple_account_token()
        headers = {"Authorization": f"Bearer {token}"}
        for index in range(3):
            challenge_response = self.client.post(
                "/v1/credits/rewarded-ad/challenge",
                headers=headers,
                json={},
            )
            self.assertEqual(challenge_response.status_code, 200, challenge_response.text)
            challenge_id = challenge_response.json()["challenge_id"]
            challenge, is_new = self.server.rewarded_ad_challenge_store.verify_event(
                challenge_id,
                f"transaction-{index}",
            )
            self.assertTrue(is_new)
            granted, _, remaining = self.server.credit_ledger.claim_rewarded_ad(
                account_key=challenge.account_key,
                event_id=f"ssv:transaction-{index}",
            )
            self.server.rewarded_ad_challenge_store.save_result(challenge_id, granted, remaining)
            response = self.client.post(
                "/v1/credits/rewarded-ad/claim",
                headers=headers,
                json={"challenge_id": challenge_id},
            )
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json()["granted"])
        limited = self.client.post(
            "/v1/credits/rewarded-ad/challenge",
            headers=headers,
            json={},
        )
        self.assertEqual(limited.status_code, 429, limited.text)
        balance = self.client.get("/v1/credits", headers=headers).json()["balance"]
        self.assertEqual(balance["available"], 35)

    def test_verified_purchase_is_granted_only_once(self) -> None:
        token, account = self.issue_apple_account_token()
        headers = {"Authorization": f"Bearer {token}"}
        verified = SimpleNamespace(
            transaction_id="transaction-123",
            product_id="com.yukitoshim.gymtrainingapp.credits50",
            credits=50,
        )
        with patch.object(self.server.purchase_verifier, "verify", return_value=verified) as verify:
            first = self.client.post(
                "/v1/credits/purchases/verify",
                headers=headers,
                json={"signed_transaction": "x" * 256},
            )
            second = self.client.post(
                "/v1/credits/purchases/verify",
                headers=headers,
                json={"signed_transaction": "x" * 256},
            )
        self.assertEqual(first.status_code, 200, first.text)
        self.assertTrue(first.json()["granted"])
        self.assertFalse(second.json()["granted"])
        self.assertEqual(second.json()["balance"]["available"], 70)
        verify.assert_called_with("x" * 256, account["app_account_token"])

    def test_verified_refund_notification_adjusts_purchase_once(self) -> None:
        token, _ = self.issue_apple_account_token()
        headers = {"Authorization": f"Bearer {token}"}
        purchase = SimpleNamespace(
            transaction_id="transaction-refunded",
            product_id="com.yukitoshim.gymtrainingapp.credits50",
            credits=50,
        )
        refund = SimpleNamespace(
            notification_id="notification-refund-1",
            transaction_id="transaction-refunded",
            product_id="com.yukitoshim.gymtrainingapp.credits50",
            credits=50,
        )
        with patch.object(self.server.purchase_verifier, "verify", return_value=purchase):
            purchased = self.client.post(
                "/v1/credits/purchases/verify",
                headers=headers,
                json={"signed_transaction": "x" * 256},
            )
        with patch.object(
            self.server.purchase_verifier,
            "verify_refund_notification",
            return_value=refund,
        ):
            first = self.client.post(
                "/v1/app-store/notifications",
                json={"signedPayload": "n" * 256},
            )
            second = self.client.post(
                "/v1/app-store/notifications",
                json={"signedPayload": "n" * 256},
            )

        self.assertEqual(purchased.status_code, 200, purchased.text)
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)
        balance = self.client.get("/v1/credits", headers=headers).json()["balance"]
        self.assertEqual(balance["available"], 20)

    def test_account_deletion_revokes_session_and_does_not_regrant_bonus(self) -> None:
        token, _ = self.issue_apple_account_token()
        self.server.apple_token_client.revoke_refresh_token.reset_mock()
        deleted = self.client.delete(
            "/v1/account",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertEqual(deleted.json()["removed_credits"], 20)
        self.server.apple_token_client.revoke_refresh_token.assert_awaited_once_with(
            "test-refresh-token"
        )
        self.assertEqual(
            self.client.get("/v1/credits", headers={"Authorization": f"Bearer {token}"}).status_code,
            401,
        )

        _, recreated = self.issue_apple_account_token()
        self.assertFalse(recreated["signup_granted"])
        self.assertEqual(recreated["credits"]["available"], 0)

    def test_account_deletion_keeps_account_when_apple_revocation_fails(self) -> None:
        token, _ = self.issue_apple_account_token("apple-revocation-failure")
        self.server.apple_token_client.revoke_refresh_token.side_effect = self.server.AppleTokenExchangeError("offline")
        deleted = self.client.delete(
            "/v1/account",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(deleted.status_code, 503, deleted.text)
        self.assertEqual(deleted.json()["detail"]["code"], "apple_revocation_failed")
        credits = self.client.get(
            "/v1/credits",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(credits.status_code, 200, credits.text)
        self.assertEqual(credits.json()["balance"]["available"], 20)

    def test_internal_health_does_not_require_public_credentials(self) -> None:
        response = self.client.get("/internal/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_usage_analytics_accepts_only_enumerated_research_properties(self) -> None:
        token = self.issue_token()
        headers = {"Authorization": f"Bearer {token}"}
        base_event = {
            "id": "00000000-0000-4000-8000-000000000099",
            "occurred_at": int(time.time()),
            "name": "daily_action_impression",
            "dimension": "workout",
            "app_version": "22",
            "locale": "ja_JP",
        }
        accepted = self.client.post(
            "/v1/analytics/events",
            headers=headers,
            json={"events": [{
                **base_event,
                "properties": {
                    "goal": "muscleGain",
                    "experience": "beginner",
                    "readiness": "normal",
                    "actionCategory": "workout",
                    "position": 0,
                    "source": "localRule",
                },
            }]},
        )
        rejected = self.client.post(
            "/v1/analytics/events",
            headers=headers,
            json={"events": [{
                **base_event,
                "id": "00000000-0000-4000-8000-000000000100",
                "properties": {"freeText": "private health note"},
            }]},
        )
        legacy = self.client.post(
            "/v1/analytics/events",
            headers=headers,
            json={"events": [{
                **base_event,
                "id": "00000000-0000-4000-8000-000000000101",
                "name": "app_opened",
                "properties": {"source": "localRule"},
            }]},
        )
        invalid_channel = self.client.post(
            "/v1/analytics/events",
            headers=headers,
            json={"events": [{
                **base_event,
                "id": "00000000-0000-4000-8000-000000000102",
                "name": "app_opened",
                "channel": "desktop",
            }]},
        )
        explicit_channel = self.client.post(
            "/v1/analytics/events",
            headers=headers,
            json={"events": [{
                **base_event,
                "id": "00000000-0000-4000-8000-000000000103",
                "name": "app_opened",
                "channel": "testflight",
            }]},
        )

        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json()["accepted"], 1)
        self.assertEqual(rejected.status_code, 422, rejected.text)
        self.assertEqual(legacy.status_code, 200, legacy.text)
        self.assertEqual(legacy.json()["accepted"], 1)
        self.assertEqual(invalid_channel.status_code, 422, invalid_channel.text)
        self.assertEqual(explicit_channel.status_code, 200, explicit_channel.text)

    def test_usage_analytics_accepts_credit_events_without_private_properties(self) -> None:
        token = self.issue_token()
        now = int(time.time())
        event_names = (
            "ai_account_registered",
            "ai_signup_grant_received",
            "ai_credit_insufficient_shown",
            "credit_store_opened",
            "rewarded_ad_started",
            "rewarded_ad_completed",
            "rewarded_credit_granted",
            "rewarded_ad_failed",
            "credit_purchase_completed",
            "credit_purchase_pending",
            "credit_purchase_cancelled",
            "credit_purchase_failed",
        )
        events = [{
            "id": f"00000000-0000-4000-8000-{index:012d}",
            "occurred_at": now,
            "name": name,
            "dimension": "fixed_category",
            "properties": {},
            "app_version": "26",
            "locale": "en_US",
            "channel": "testflight",
        } for index, name in enumerate(event_names, start=700)]

        response = self.client.post(
            "/v1/analytics/events",
            headers={"Authorization": f"Bearer {token}"},
            json={"events": events},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["accepted"], len(event_names))

    def test_gateway_secret_blocks_direct_public_api_access_when_enabled(self) -> None:
        token = self.issue_token()
        original_secret = self.server.GATEWAY_SHARED_SECRET
        self.server.GATEWAY_SHARED_SECRET = "gateway-test-secret"
        try:
            denied = self.client.get(
                "/v1/coaches",
                headers={"Authorization": f"Bearer {token}"},
            )
            allowed = self.client.get(
                "/v1/coaches",
                headers={
                    "Authorization": f"Bearer {token}",
                    "X-BodyMode-Gateway-Key": "gateway-test-secret",
                },
            )
        finally:
            self.server.GATEWAY_SHARED_SECRET = original_secret

        self.assertEqual(denied.status_code, 403)
        self.assertEqual(denied.json()["detail"]["code"], "gateway_required")
        self.assertEqual(allowed.status_code, 200, allowed.text)

    def test_usage_endpoint_returns_all_feature_limits(self) -> None:
        token = self.issue_token()
        response = self.client.get(
            "/v1/usage",
            headers={"Authorization": f"Bearer {token}"},
        )

        self.assertEqual(response.status_code, 200, response.text)
        features = {item["feature"]: item for item in response.json()["features"]}
        self.assertEqual(features["chat"]["limit"], 5)
        self.assertEqual(features["meal"]["remaining"], 3)
        self.assertIn("reset_at", features["weekly_report"])

    def test_usage_endpoint_is_scaled_for_testflight_header(self) -> None:
        token = self.issue_token()
        response = self.client.get(
            "/v1/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "X-BodyMode-Distribution-Channel": "testflight",
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        features = {item["feature"]: item for item in data["features"]}
        self.assertEqual(data["distribution_channel"], "testflight")
        self.assertEqual(features["chat"]["limit"], 10)
        self.assertEqual(features["meal"]["limit"], 6)
        self.assertEqual(features["weekly_report"]["limit"], 2)

    def test_usage_endpoint_defaults_missing_or_invalid_channel_to_app_store(self) -> None:
        token = self.issue_token()
        response = self.client.get(
            "/v1/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "X-BodyMode-Distribution-Channel": "desktop",
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        features = {item["feature"]: item for item in data["features"]}
        self.assertEqual(data["distribution_channel"], "app_store")
        self.assertEqual(features["chat"]["limit"], 5)
        self.assertEqual(features["meal"]["limit"], 3)

    def test_owner_subject_is_quota_exempt_without_disabling_global_enforcement(self) -> None:
        normal = self.client.get(
            "/v1/usage",
            headers={"Authorization": f"Bearer {self.issue_token()}"},
        )
        owner = self.client.get(
            "/v1/usage",
            headers={"Authorization": f"Bearer {self.issue_owner_token()}"},
        )

        self.assertTrue(normal.json()["enforced"])
        self.assertFalse(owner.json()["enforced"])
        self.assertTrue(self.server.AI_QUOTA_ENFORCEMENT)

    def test_quota_exceeded_returns_structured_429(self) -> None:
        from usage_quota import QuotaPolicy

        self.server.AI_CREDIT_ENFORCEMENT = False
        token = self.issue_token()
        self.server.usage_ledger.policies["chat"] = QuotaPolicy(
            "chat",
            limit=1,
            window_seconds=86_400,
            calendar_day=True,
        )

        async def fake_ollama_json(prompt, fallback, images=None, format_schema=None):
            return fallback

        self.server.ollama_json = fake_ollama_json
        payload = {
            "coach_id": "hypertrophy",
            "purpose": "chat",
            "message": "次回の重量を相談したい",
            "context": {},
            "recent_messages": [],
        }
        headers = {"Authorization": f"Bearer {token}"}
        first = self.client.post(
            "/v1/agents/chat",
            headers={**headers, "X-Request-ID": "quota-request-1"},
            json=payload,
        )
        limited = self.client.post(
            "/v1/agents/chat",
            headers={**headers, "X-Request-ID": "quota-request-2"},
            json=payload,
        )

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(limited.status_code, 429, limited.text)
        detail = limited.json()["detail"]
        self.assertEqual(detail["code"], "daily_quota_exceeded")
        self.assertEqual(detail["feature"], "chat")
        self.assertEqual(detail["remaining"], 0)
        self.assertIn("Retry-After", limited.headers)

    def test_credit_account_uses_balance_without_legacy_daily_quota(self) -> None:
        from usage_quota import QuotaPolicy

        token, _ = self.issue_apple_account_token()
        self.server.usage_ledger.policies["chat"] = QuotaPolicy(
            "chat",
            limit=1,
            window_seconds=86_400,
            calendar_day=True,
        )
        payload = {
            "coach_id": "hypertrophy",
            "purpose": "chat",
            "message": "次回の重量を相談したい",
            "context": {},
            "recent_messages": [],
        }
        response = {
            "reply": "少しずつ増やしましょう。",
            "memory_candidates": [],
            "evidence": [],
            "evidence_status": {"state": "unavailable"},
            "evidence_claims": [],
        }
        with patch.object(
            self.server,
            "_agent_chat_impl",
            new=AsyncMock(return_value=response),
        ):
            first = self.client.post(
                "/v1/agents/chat",
                headers={"Authorization": f"Bearer {token}", "X-Request-ID": "paid-1"},
                json=payload,
            )
            second = self.client.post(
                "/v1/agents/chat",
                headers={"Authorization": f"Bearer {token}", "X-Request-ID": "paid-2"},
                json=payload,
            )

        usage = self.client.get(
            "/v1/usage",
            headers={"Authorization": f"Bearer {token}"},
        ).json()
        balance = self.client.get(
            "/v1/credits",
            headers={"Authorization": f"Bearer {token}"},
        ).json()["balance"]

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)
        self.assertFalse(usage["enforced"])
        self.assertTrue(usage["credits"]["enforced"])
        self.assertEqual(balance["available"], 18)

    def test_token_issue_endpoint_has_a_separate_client_rate_limit(self) -> None:
        self.server.TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE = 2
        self.server.TOKEN_ISSUE_GLOBAL_LIMIT_PER_MINUTE = 100
        self.server._token_issue_events.clear()
        request = {
            "installation_id": "00000000-0000-4000-8000-000000000099",
            "app_version": "1.0",
        }

        first = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": "Bearer invalid-one"},
            json=request,
        )
        second = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": "Bearer invalid-two"},
            json=request,
        )
        limited = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": f"Bearer {self.enrollment_key}"},
            json=request,
        )

        self.assertEqual(first.status_code, 401)
        self.assertEqual(second.status_code, 401)
        self.assertEqual(limited.status_code, 429)
        self.assertEqual(limited.headers["Retry-After"], "60")

    def test_token_issue_rate_limit_isolated_by_installation(self) -> None:
        self.server.TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE = 1
        self.server.TOKEN_ISSUE_GLOBAL_LIMIT_PER_MINUTE = 100
        self.server._token_issue_events.clear()

        first = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": f"Bearer {self.enrollment_key}"},
            json={"installation_id": "00000000-0000-4000-8000-000000000101", "app_version": "1.0"},
        )
        second = self.client.post(
            "/v1/auth/token",
            headers={"Authorization": f"Bearer {self.enrollment_key}"},
            json={"installation_id": "00000000-0000-4000-8000-000000000102", "app_version": "1.0"},
        )

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)

    def test_request_id_is_preserved_or_safely_generated(self) -> None:
        supplied = self.client.get(
            "/internal/health",
            headers={"X-Request-ID": "bodymode-test-123"},
        )
        generated = self.client.get(
            "/internal/health",
            headers={"X-Request-ID": "invalid request id with spaces"},
        )

        self.assertEqual(supplied.headers["X-Request-ID"], "bodymode-test-123")
        self.assertNotEqual(generated.headers["X-Request-ID"], "invalid request id with spaces")
        uuid.UUID(generated.headers["X-Request-ID"])

    def test_ollama_failure_returns_retryable_service_unavailable(self) -> None:
        token, _ = self.issue_apple_account_token()

        async def failing_post(*args, **kwargs):
            raise RuntimeError("model unavailable")

        original_client = self.server.httpx.AsyncClient

        class FailingAsyncClient:
            async def __aenter__(self):
                return self

            async def __aexit__(self, exc_type, exc, traceback):
                return False

            post = failing_post

        self.server.httpx.AsyncClient = lambda *args, **kwargs: FailingAsyncClient()
        try:
            response = self.client.post(
                "/v1/agents/chat",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "coach_id": "hypertrophy",
                    "message": "次回の重量を相談したい",
                    "context": {},
                    "recent_messages": [],
                },
            )
        finally:
            self.server.httpx.AsyncClient = original_client

        self.assertEqual(response.status_code, 503, response.text)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "model_unavailable")
        self.assertIn("再試行", detail["message"])
        self.assertEqual(response.headers["Retry-After"], "60")

    def test_ollama_prompt_compaction_preserves_instruction_and_latest_input(self) -> None:
        prompt = "INSTRUCTION:" + ("長い入力" * 2_000) + ":LATEST-QUESTION"

        compacted = self.server._compact_ollama_prompt(prompt, 240)

        self.assertLessEqual(len(compacted), 240)
        self.assertTrue(compacted.startswith("INSTRUCTION:"))
        self.assertTrue(compacted.endswith(":LATEST-QUESTION"))
        self.assertIn("中間部分を省略", compacted)

    def test_ollama_request_caps_prompt_and_reserves_output_tokens(self) -> None:
        captured_payload = {}

        class SuccessfulResponse:
            def raise_for_status(self):
                return None

            def json(self):
                return {"response": '{"ok": true}'}

        class CapturingAsyncClient:
            def __init__(self, *args, **kwargs):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, exc_type, exc, traceback):
                return False

            async def post(self, url, json):
                captured_payload.update(json)
                return SuccessfulResponse()

        original_client = self.server.httpx.AsyncClient
        original_limit = self.server.OLLAMA_MAX_PROMPT_CHARACTERS
        self.server.httpx.AsyncClient = CapturingAsyncClient
        self.server.OLLAMA_MAX_PROMPT_CHARACTERS = 220
        try:
            result = asyncio.run(
                self.server.ollama_json(
                    "IMPORTANT:" + ("context" * 300) + ":CURRENT-QUESTION",
                    {},
                )
            )
        finally:
            self.server.httpx.AsyncClient = original_client
            self.server.OLLAMA_MAX_PROMPT_CHARACTERS = original_limit

        self.assertEqual(result, {"ok": True})
        self.assertLessEqual(len(captured_payload["prompt"]), 220)
        self.assertTrue(captured_payload["prompt"].startswith("IMPORTANT:"))
        self.assertTrue(captured_payload["prompt"].endswith(":CURRENT-QUESTION"))
        self.assertEqual(
            captured_payload["options"],
            {
                "num_ctx": self.server.OLLAMA_CONTEXT_WINDOW,
                "num_predict": self.server.OLLAMA_NUM_PREDICT,
            },
        )

    def test_ollama_queue_rejects_second_request_without_calling_model(self) -> None:
        original_timeout = self.server.INFERENCE_QUEUE_TIMEOUT_SECONDS
        self.server.INFERENCE_QUEUE_TIMEOUT_SECONDS = 0.01

        async def run_while_busy():
            await self.server._inference_semaphore.acquire()
            try:
                with self.assertRaises(self.server.HTTPException) as captured:
                    await self.server.ollama_json("prompt", {})
                self.assertEqual(captured.exception.status_code, 503)
                self.assertEqual(captured.exception.detail["code"], "server_busy")
                self.assertIn("混み合っています", captured.exception.detail["message"])
            finally:
                self.server._inference_semaphore.release()

        try:
            asyncio.run(run_while_busy())
        finally:
            self.server.INFERENCE_QUEUE_TIMEOUT_SECONDS = original_timeout

    def test_health_reports_recent_inference_failure_as_degraded(self) -> None:
        token = self.issue_token()

        async def available_ollama():
            return {"reachable": True, "model_available": True, "models": ["gemma4:12b"]}

        original_status = self.server.ollama_status
        self.server.ollama_status = available_ollama
        with self.server._inference_state_lock:
            self.server._inference_state["last_success_at"] = 1
            self.server._inference_state["last_failure_at"] = 2
            self.server._inference_state["last_error_type"] = "ReadTimeout"
        try:
            response = self.client.get(
                "/v1/health",
                headers={"Authorization": f"Bearer {token}"},
            )
        finally:
            self.server.ollama_status = original_status

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["status"], "degraded")
        self.assertFalse(response.json()["inference_ready"])
        self.assertEqual(response.json()["last_inference_error"], "ReadTimeout")

    def test_token_issue_audit_log_never_contains_credentials_or_installation_id(self) -> None:
        installation_id = "00000000-0000-4000-8000-sensitive-device"
        with self.assertLogs("bodymode.auth", level="INFO") as captured:
            response = self.client.post(
                "/v1/auth/token",
                headers={"Authorization": f"Bearer {self.enrollment_key}"},
                json={"installation_id": installation_id, "app_version": "secret-build-name"},
            )

        self.assertEqual(response.status_code, 200, response.text)
        output = "\n".join(captured.output)
        self.assertIn('"result":"issued"', output)
        self.assertNotIn(self.enrollment_key, output)
        self.assertNotIn(installation_id, output)
        self.assertNotIn("secret-build-name", output)

    def test_monthly_report_uses_authenticated_route_and_returns_review_shape(self) -> None:
        token, _ = self.issue_apple_account_token()

        async def fake_ollama_json(prompt, fallback, images=None, format_schema=None):
            self.assertIn("月次レビュー案", prompt)
            return {
                "input_summary": "30日分の記録",
                "output_comment": "月次差分",
                "action_suggestion": "翌月目標案",
            }

        self.server.ollama_json = fake_ollama_json
        response = self.client.post(
            "/v1/reports/monthly",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "profile_goal": "筋肥大",
                "coach_id": "hypertrophy",
                "experience_level": "beginner",
                "body_logs": [],
                "meals": [],
                "workouts": [],
                "body_photos": [],
                "sensor_metrics": [],
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["action_suggestion"], "翌月目標案")

    def test_weekly_report_returns_structured_coaching_sections(self) -> None:
        token, _ = self.issue_apple_account_token()

        async def fake_ollama_json(prompt, fallback, images=None, format_schema=None):
            self.assertIn('"good_points"', prompt)
            return {
                "input_summary": "7日分の記録",
                "output_comment": "継続できています。",
                "action_suggestion": "次週も続けましょう。",
                "good_points": ["週3回運動できた"],
                "challenges": ["睡眠記録が少ない"],
                "rationales": ["運動履歴3件を確認"],
                "next_actions": ["睡眠を3日記録する"],
            }

        self.server.ollama_json = fake_ollama_json
        response = self.client.post(
            "/v1/reports/weekly",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "profile_goal": "健康維持",
                "coach_id": "wellness",
                "experience_level": "beginner",
                "body_logs": [],
                "meals": [],
                "workouts": ["運動1", "運動2", "運動3"],
                "body_photos": [],
                "sensor_metrics": [],
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["good_points"], ["週3回運動できた"])
        self.assertEqual(response.json()["challenges"], ["睡眠記録が少ない"])
        self.assertEqual(response.json()["rationales"], ["運動履歴3件を確認"])
        self.assertEqual(response.json()["next_actions"], ["睡眠を3日記録する"])

    def test_agent_chat_returns_only_evidence_used_by_the_model(self) -> None:
        from evidence_rag import EvidenceDocument

        token, _ = self.issue_apple_account_token()
        self.server.evidence_store.upsert_documents(
            [
                EvidenceDocument(
                    pmid="12345678",
                    pmcid="",
                    doi="10.1000/bodymode-test",
                    title="Resistance training volume and muscle hypertrophy",
                    abstract_text="A systematic review of resistance training volume.",
                    authors="Test Author",
                    journal="Test Journal",
                    publication_year=2025,
                    publication_types=("Systematic Review",),
                    keywords=("hypertrophy", "resistance training"),
                    source_url="https://pubmed.ncbi.nlm.nih.gov/12345678/",
                    is_open_access=False,
                    retracted=False,
                    corrected=False,
                    study_type="systematic_review",
                    quality_score=0.9,
                    source_updated_at="2025-01-01",
                    topics=("hypertrophy",),
                )
            ]
        )
        captured_prompts = []
        captured_schemas = []

        async def fake_ollama_json(prompt, fallback, images=None, format_schema=None):
            captured_prompts.append(prompt)
            captured_schemas.append(format_schema)
            return {
                "reply": "セット数は段階的に増やしましょう。[E1]",
                "memory_candidates": [],
                "evidence_ids": ["E1", "E8"],
            }

        self.server.ollama_json = fake_ollama_json
        response = self.client.post(
            "/v1/agents/chat",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "coach_id": "hypertrophy",
                "message": "筋肥大のためにセット数を増やすべき？",
                "context": {},
                "recent_messages": [],
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual([item["id"] for item in body["evidence"]], ["PMID:12345678"])
        self.assertEqual(body["evidence_status"]["state"], "ready")
        self.assertIn("[E1] PMID:12345678", captured_prompts[-1])
        evidence_schema = captured_schemas[-1]["properties"]["evidence_ids"]
        self.assertEqual(evidence_schema["minItems"], 1)
        self.assertEqual(evidence_schema["items"]["enum"], ["E1"])

    def test_meal_image_prompt_renders_json_example_without_format_error(self) -> None:
        token, _ = self.issue_apple_account_token()
        captured_prompts = []

        async def fake_ollama_json(prompt, fallback, images=None, format_schema=None):
            captured_prompts.append(prompt)
            return fallback

        self.server.ollama_json = fake_ollama_json
        self.server.calorie_clip_runtime.predict = lambda _: 321.0
        response = self.client.post(
            "/v1/meals/analyze-image",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "image_base64": "YWJjZGVmZ2hpamtsbW5vcA==",
                "meal_type": "lunch",
                "memo": "",
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["calories"], 321.0)
        self.assertIn('{\n  "meal_name": "料理名"', captured_prompts[-1])
        self.assertIn('{"name": "食材名"', captured_prompts[-1])

    def test_body_photo_set_prompt_normalizes_partial_previous_metrics_and_deltas(self) -> None:
        from usage_quota import QuotaPolicy

        self.server.usage_ledger.policies["body_photo"] = QuotaPolicy(
            "body_photo",
            limit=2,
            window_seconds=86_400,
            calendar_day=True,
        )
        token, _ = self.issue_apple_account_token()
        captured_prompts = []

        async def fake_ollama_json(prompt, fallback, images=None, format_schema=None):
            captured_prompts.append(prompt)
            return fallback

        self.server.ollama_json = fake_ollama_json
        payload = {
            "photos": [{"image_base64": "a" * 16, "angle": "front"}],
            "comparison_photos": [],
            "memo": "",
            "context": {
                "current_metrics": ["体重: 70 kg"],
                "previous_metrics": {
                    "weight_kg": 70.4,
                    "waist_cm": 82.1,
                    "body_fat_percent": 16.0,
                },
                "metric_deltas": {"weight_kg": -0.4, "body_fat_percent": -0.8},
            },
        }

        response = self.client.post(
            "/v1/body-photos/analyze-set",
            headers={"Authorization": f"Bearer {token}"},
            json=payload,
        )

        self.assertEqual(response.status_code, 200, response.text)
        prompt = captured_prompts[-1]
        self.assertIn(
            "前回の実測値: 体重 70.4 kg / 腹囲 82.1 cm / 体脂肪率 16 %",
            prompt,
        )
        self.assertIn(
            "実測差分（当日 - 前回）: 体重 -0.4 kg / 体脂肪率 -0.8 %",
            prompt,
        )
        self.assertNotIn("実測差分（当日 - 前回）: 体重 -0.4 kg / 腹囲", prompt)
        self.assertIn("欠測している実測値は推測・補完せず", prompt)

        legacy_payload = {
            "photos": [{"image_base64": "b" * 16, "angle": "side"}],
            "memo": "",
            "context": {"profile_goal": "健康維持"},
        }
        legacy_response = self.client.post(
            "/v1/body-photos/analyze-set",
            headers={"Authorization": f"Bearer {token}"},
            json=legacy_payload,
        )
        self.assertEqual(legacy_response.status_code, 200, legacy_response.text)
        self.assertIn("前回の実測値: なし", captured_prompts[-1])
        self.assertIn("実測差分（当日 - 前回）: なし", captured_prompts[-1])

    def test_body_photo_reference_estimate_is_bounded_and_always_low_confidence(self) -> None:
        normalized = self.server.normalize_body_photo_estimates(
            [
                {
                    "metric": "body_fat_percent",
                    "lower_bound": 18,
                    "upper_bound": 19,
                    "unit": "kg",
                    "confidence": "high",
                    "rationale": "写真からの参考",
                },
                {
                    "metric": "waist_cm",
                    "lower_bound": 70,
                    "upper_bound": 80,
                },
            ]
        )

        self.assertEqual(len(normalized), 1)
        self.assertEqual(normalized[0]["metric"], "body_fat_percent")
        self.assertEqual(normalized[0]["lower_bound"], 18)
        self.assertEqual(normalized[0]["upper_bound"], 22)
        self.assertEqual(normalized[0]["unit"], "%")
        self.assertEqual(normalized[0]["confidence"], "low")

    def test_daily_recommendation_reply_falls_back_to_keep_existing_json(self) -> None:
        reply = self.server.normalize_daily_recommendation_reply(
            "提案はそのままでよいと思います。",
            "[BODYMODE_DAILY_JSON]\n現在の調子: tired",
        )

        body = json.loads(reply)
        self.assertTrue(body["keep_existing"])
        self.assertEqual(body["readiness_level"], "tired")
        self.assertEqual(body["actions"], [])

    def test_daily_recommendation_reply_removes_invalid_actions_and_ids(self) -> None:
        reply = self.server.normalize_daily_recommendation_reply(
            json.dumps(
                {
                    "keep_existing": False,
                    "readiness_level": "TIRED",
                    "summary": "負荷を調整",
                    "change_reason": "睡眠不足",
                    "actions": [
                        {
                            "id": "not-a-uuid",
                            "category": "recovery",
                            "title": "回復を優先",
                            "target": 1,
                            "rationale": "睡眠が短い",
                        },
                        {"category": "unknown", "title": "不正"},
                    ],
                },
                ensure_ascii=False,
            ),
            "[BODYMODE_DAILY_JSON]\n現在の調子: normal",
        )

        body = json.loads(reply)
        self.assertFalse(body["keep_existing"])
        self.assertEqual(body["readiness_level"], "tired")
        self.assertEqual(len(body["actions"]), 1)
        self.assertNotIn("id", body["actions"][0])


if __name__ == "__main__":
    unittest.main()
