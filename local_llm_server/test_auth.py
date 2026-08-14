import hashlib
import importlib
import json
import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

from fastapi.testclient import TestClient


class AuthenticationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        enrollment_key = "family-test-enrollment-key"
        enrollment_hash = hashlib.sha256(enrollment_key.encode("utf-8")).hexdigest()
        enrollment_file = root / "enrollment_keys.json"
        enrollment_file.write_text(
            json.dumps({"family-test": f"sha256:{enrollment_hash}"}),
            encoding="utf-8",
        )
        os.environ.update(
            {
                "LOCAL_AI_API_KEY": "legacy-disabled-for-test",
                "AI_AUTH_MODE": "token_required",
                "AI_TOKEN_SIGNING_SECRET": "test-signing-secret-with-more-than-32-characters",
                "AI_TOKEN_TTL_SECONDS": "3600",
                "AI_RATE_LIMIT_PER_MINUTE": "30",
                "AI_TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE": "8",
                "AI_TOKEN_FAILURE_DELAY_SECONDS": "0",
                "AI_ENROLLMENT_KEYS_FILE": str(enrollment_file),
                "AI_AUTH_STATE_PATH": str(root / "auth-state.json"),
                "EVIDENCE_RAG_ENABLED": "1",
                "EVIDENCE_RAG_DB_PATH": str(root / "evidence.sqlite3"),
            }
        )
        sys.modules.pop("main", None)
        self.server = importlib.import_module("main")
        self.client = TestClient(self.server.app)
        self.enrollment_key = enrollment_key

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

    def test_internal_health_does_not_require_public_credentials(self) -> None:
        response = self.client.get("/internal/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

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
        token = self.issue_token()

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
        self.assertIn("再試行", response.json()["detail"])

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
        token = self.issue_token()

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
        token = self.issue_token()

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

        token = self.issue_token()
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
        token = self.issue_token()
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
        token = self.issue_token()
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
