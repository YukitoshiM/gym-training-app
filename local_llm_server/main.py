import json
import logging
import os
import re
import base64
import hashlib
import hmac
import secrets
import threading
import time
import asyncio
from collections import defaultdict, deque
from pathlib import Path
from typing import Any, Optional

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, model_validator
from calorie_clip_runtime import calorie_clip_runtime
from coach_profiles import COMMON_SAFETY_RULES, COACH_PROFILES, get_coach_profile
from evidence_rag import EvidenceStore, citation_dict


APP_NAME = "Gym Training Local LLM"
API_KEY = os.getenv("LOCAL_AI_API_KEY", "dev-local-key")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma4:12b")
OLLAMA_REQUEST_TIMEOUT_SECONDS = max(
    30.0,
    min(float(os.getenv("OLLAMA_REQUEST_TIMEOUT_SECONDS", "180")), 600.0),
)
AUTH_MODE = os.getenv("AI_AUTH_MODE", "compat").strip().lower()
TOKEN_TTL_SECONDS = max(300, min(int(os.getenv("AI_TOKEN_TTL_SECONDS", "86400")), 604800))
RATE_LIMIT_PER_MINUTE = max(1, int(os.getenv("AI_RATE_LIMIT_PER_MINUTE", "30")))
TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE = max(
    1,
    min(int(os.getenv("AI_TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE", "8")), 120),
)
TOKEN_FAILURE_DELAY_SECONDS = max(
    0.0,
    min(float(os.getenv("AI_TOKEN_FAILURE_DELAY_SECONDS", "0.25")), 2.0),
)
MAX_CONCURRENT_INFERENCE = max(1, min(int(os.getenv("AI_MAX_CONCURRENT_INFERENCE", "2")), 8))
TOKEN_SIGNING_SECRET = os.getenv("AI_TOKEN_SIGNING_SECRET", "")
ENROLLMENT_KEYS_FILE = os.getenv("AI_ENROLLMENT_KEYS_FILE", "")
AUTH_STATE_PATH = Path(
    os.getenv(
        "AI_AUTH_STATE_PATH",
        str(Path.home() / "Library/Application Support/BodyMode/ai-auth-state.json"),
    )
)
EVIDENCE_RAG_ENABLED = os.getenv("EVIDENCE_RAG_ENABLED", "1").strip().lower() not in {
    "0",
    "false",
    "no",
}
EVIDENCE_RAG_DB_PATH = Path(
    os.getenv(
        "EVIDENCE_RAG_DB_PATH",
        str(Path.home() / "Library/Application Support/BodyMode/evidence-rag.sqlite3"),
    )
).expanduser()
EVIDENCE_EMBEDDING_MODEL = os.getenv("EVIDENCE_EMBEDDING_MODEL", "bge-m3")

if AUTH_MODE not in {"compat", "token_required"}:
    raise RuntimeError("AI_AUTH_MODE must be compat or token_required")
if AUTH_MODE == "token_required" and not TOKEN_SIGNING_SECRET:
    raise RuntimeError("AI_TOKEN_SIGNING_SECRET is required when AI_AUTH_MODE=token_required")

app = FastAPI(title=APP_NAME)
WEB_DIR = Path(__file__).resolve().parent / "web"
_inference_semaphore = asyncio.Semaphore(MAX_CONCURRENT_INFERENCE)
evidence_store = EvidenceStore(EVIDENCE_RAG_DB_PATH)


@app.get("/", include_in_schema=False)
async def web_app() -> FileResponse:
    return FileResponse(WEB_DIR / "index.html")


@app.get("/internal/health", include_in_schema=False)
async def internal_health() -> dict[str, str]:
    return {"status": "ok"}


class RequestCoachContext(BaseModel):
    coach_id: str = "body_recomposition"
    coach_name: str = "BodyModeトレーナー"
    coaching_style: str = "穏やかで現実的"
    promise: str = "記録に基づいて次の行動を提案する"
    focus_areas: list[str] = []
    approach: list[str] = []
    boundaries: list[str] = []


class MealAnalysisRequest(BaseModel):
    image_base64: str = Field(min_length=16, max_length=8_000_000)
    meal_type: str = "lunch"
    memo: str = ""
    coach: Optional[RequestCoachContext] = None


class MealTextAnalysisRequest(BaseModel):
    items: list[str] = Field(min_length=1, max_length=20)
    meal_type: str = "lunch"
    memo: str = ""
    coach: Optional[RequestCoachContext] = None


class MealAIDraftItem(BaseModel):
    name: str
    amount: str
    calories: float
    protein: float
    fat: float
    carbs: float


class MealAIDraft(BaseModel):
    mealName: str = Field(alias="meal_name")
    calories: float
    protein: float
    fat: float
    carbs: float
    confidence: str
    comment: str
    items: list[MealAIDraftItem]


MEAL_DRAFT_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "meal_name": {"type": "string"},
        "calories": {"type": "number"},
        "protein": {"type": "number"},
        "fat": {"type": "number"},
        "carbs": {"type": "number"},
        "confidence": {"type": "string", "enum": ["low", "medium", "high"]},
        "comment": {"type": "string"},
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "amount": {"type": "string"},
                    "calories": {"type": "number"},
                    "protein": {"type": "number"},
                    "fat": {"type": "number"},
                    "carbs": {"type": "number"},
                },
                "required": ["name", "amount", "calories", "protein", "fat", "carbs"],
            },
        },
    },
    "required": [
        "meal_name",
        "calories",
        "protein",
        "fat",
        "carbs",
        "confidence",
        "comment",
        "items",
    ],
}


def agent_chat_json_schema(evidence_count: int) -> dict[str, Any]:
    evidence_ids = [f"E{index}" for index in range(1, evidence_count + 1)]
    evidence_rules: dict[str, Any] = {
        "type": "array",
        "items": {"type": "string", "enum": evidence_ids} if evidence_ids else {"type": "string"},
        "uniqueItems": True,
        "maxItems": len(evidence_ids),
    }
    if evidence_ids:
        evidence_rules["minItems"] = 1
    else:
        evidence_rules["maxItems"] = 0
    return {
        "type": "object",
        "properties": {
            "reply": {"type": "string"},
            "memory_candidates": {
                "type": "array",
                "maxItems": 3,
                "items": {
                    "type": "object",
                    "properties": {
                        "content": {"type": "string"},
                        "reason": {"type": "string"},
                    },
                    "required": ["content", "reason"],
                },
            },
            "evidence_ids": evidence_rules,
        },
        "required": ["reply", "memory_candidates", "evidence_ids"],
    }


class BodyPhotoAnalysisRequest(BaseModel):
    image_base64: str = Field(min_length=16, max_length=8_000_000)
    angle: str = "front"
    memo: str = ""


class BodyPhotoSetImage(BaseModel):
    image_base64: str = Field(min_length=16, max_length=8_000_000)
    angle: str


class BodyPhotoMetricValues(BaseModel):
    weight_kg: Optional[float] = None
    waist_cm: Optional[float] = None
    body_fat_percent: Optional[float] = None


class BodyPhotoAnalysisContext(BaseModel):
    profile_goal: str = ""
    outcome_style: str = ""
    focus_areas: list[str] = []
    experience_level: str = ""
    current_metrics: list[str] = []
    previous_capture_date: Optional[str] = None
    previous_summary: Optional[str] = None
    previous_metrics: Optional[BodyPhotoMetricValues] = None
    metric_deltas: Optional[BodyPhotoMetricValues] = None
    coach: Optional[RequestCoachContext] = None


class BodyPhotoSetAnalysisRequest(BaseModel):
    photos: list[BodyPhotoSetImage] = Field(min_length=1, max_length=4)
    comparison_photos: list[BodyPhotoSetImage] = Field(default=[], max_length=4)
    memo: str = ""
    context: Optional[BodyPhotoAnalysisContext] = None


class BodyPhotoAIComment(BaseModel):
    summary: str
    abdomen: str
    waist: str
    posture: str
    score: Optional[float] = None
    confidence: str
    goal_relevance: Optional[str] = None
    positive_findings: list[str] = []
    observed_changes: list[str] = []
    next_actions: list[str] = []


class WeeklyReportRequest(BaseModel):
    profile_goal: str
    coach_id: str = "body_recomposition"
    coach: Optional[RequestCoachContext] = None
    experience_level: str = "beginner"
    body_logs: list[str] = []
    meals: list[str] = []
    workouts: list[str] = []
    body_photos: list[str] = []
    sensor_metrics: list[str] = []


class WeeklyReportResponse(BaseModel):
    input_summary: str
    output_comment: str
    action_suggestion: str
    good_points: list[str] = []
    challenges: list[str] = []
    rationales: list[str] = []
    next_actions: list[str] = []


class CoachSummary(BaseModel):
    id: str
    name: str
    identity: str
    priorities: list[str]


class AgentMessage(BaseModel):
    role: str
    content: str


class AgentChatRequest(BaseModel):
    coach_id: str = "body_recomposition"
    message: str = Field(min_length=1, max_length=4000)
    context: dict[str, Any] = Field(default_factory=dict)
    recent_messages: list[AgentMessage] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def validate_context_size(self) -> "AgentChatRequest":
        payload_size = len(json.dumps(self.context, ensure_ascii=False))
        payload_size += len(
            json.dumps([message.model_dump() for message in self.recent_messages], ensure_ascii=False)
        )
        if payload_size > 60_000:
            raise ValueError("context and recent_messages must fit within 60,000 characters")
        return self


class MemoryCandidate(BaseModel):
    content: str
    reason: str


class EvidenceCitationResponse(BaseModel):
    id: str
    title: str
    year: Optional[int] = None
    study_type: str
    confidence: str
    url: str
    doi: str = ""
    relevance: float


class EvidenceStatusResponse(BaseModel):
    state: str
    confidence: str = "insufficient"
    last_updated_at: Optional[str] = None
    searched_documents: int = 0


class AgentChatResponse(BaseModel):
    reply: str
    memory_candidates: list[MemoryCandidate]
    evidence: list[EvidenceCitationResponse] = Field(default_factory=list)
    evidence_status: EvidenceStatusResponse


class AccessTokenRequest(BaseModel):
    installation_id: str = Field(min_length=16, max_length=128)
    app_version: str = Field(default="", max_length=40)


class AccessTokenResponse(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int


class AuthenticatedClient(BaseModel):
    subject: str
    installation_id: str
    token_id: str
    expires_at: int


_auth_lock = threading.Lock()
_rate_limit_events: dict[str, deque[float]] = defaultdict(deque)
_token_issue_events: dict[str, deque[float]] = defaultdict(deque)
_auth_audit_logger = logging.getLogger("bodymode.auth")
_auth_audit_logger.setLevel(logging.INFO)
if not _auth_audit_logger.handlers:
    _auth_audit_handler = logging.StreamHandler()
    _auth_audit_handler.setFormatter(logging.Formatter("%(message)s"))
    _auth_audit_logger.addHandler(_auth_audit_handler)
_auth_audit_logger.propagate = False


def _base64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _base64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _signing_secret() -> bytes:
    if TOKEN_SIGNING_SECRET:
        return TOKEN_SIGNING_SECRET.encode("utf-8")
    return hashlib.sha256(f"bodymode-compat:{API_KEY}".encode("utf-8")).digest()


def _load_auth_state() -> dict[str, int]:
    try:
        content = json.loads(AUTH_STATE_PATH.read_text(encoding="utf-8"))
        revoked = content.get("revoked_tokens", {})
        if not isinstance(revoked, dict):
            return {}
        now = int(time.time())
        return {
            str(token_id): int(expiry)
            for token_id, expiry in revoked.items()
            if int(expiry) > now
        }
    except (OSError, ValueError, TypeError):
        return {}


_revoked_tokens = _load_auth_state()


def _persist_auth_state() -> None:
    now = int(time.time())
    active = {token_id: expiry for token_id, expiry in _revoked_tokens.items() if expiry > now}
    AUTH_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = AUTH_STATE_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps({"revoked_tokens": active}), encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(AUTH_STATE_PATH)


def _load_enrollment_keys() -> dict[str, str]:
    if not ENROLLMENT_KEYS_FILE:
        return {}
    try:
        content = json.loads(Path(ENROLLMENT_KEYS_FILE).read_text(encoding="utf-8"))
        if not isinstance(content, dict):
            return {}
        return {str(subject): str(key) for subject, key in content.items() if str(key)}
    except (OSError, ValueError, TypeError):
        return {}


def _bearer_token(authorization: Optional[str]) -> str:
    prefix = "Bearer "
    if not authorization or not authorization.startswith(prefix):
        raise HTTPException(status_code=401, detail="Authorization is required")
    token = authorization[len(prefix):].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Authorization is required")
    return token


def _enrollment_subject(credential: str) -> Optional[str]:
    for subject, expected in _load_enrollment_keys().items():
        candidate_digest = hashlib.sha256(credential.encode("utf-8")).hexdigest()
        expected_digest = expected.removeprefix("sha256:")
        if hmac.compare_digest(candidate_digest, expected_digest):
            return subject
    if AUTH_MODE == "compat" and API_KEY and hmac.compare_digest(credential, API_KEY):
        return "compat-user"
    return None


def _audit_fingerprint(value: str) -> str:
    digest = hmac.new(_signing_secret(), value.encode("utf-8"), hashlib.sha256).hexdigest()
    return digest[:16]


def _audit_token_issue(
    *,
    result: str,
    request: Request,
    installation_id: str,
    app_version: str,
    subject: Optional[str] = None,
) -> None:
    remote_host = request.client.host if request.client else "unknown"
    event = {
        "event": "access_token_issue",
        "result": result,
        "remote": _audit_fingerprint(remote_host),
        "installation": _audit_fingerprint(installation_id),
        "app_version": _audit_fingerprint(app_version or "unknown"),
    }
    if subject:
        event["subject"] = _audit_fingerprint(subject)
    _auth_audit_logger.info(json.dumps(event, separators=(",", ":"), sort_keys=True))


def _enforce_token_issue_rate_limit(request: Request) -> None:
    now = time.monotonic()
    remote_host = request.client.host if request.client else "unknown"
    key = f"token:{remote_host}"
    with _auth_lock:
        events = _token_issue_events[key]
        while events and now - events[0] >= 60:
            events.popleft()
        if len(events) >= TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE:
            raise HTTPException(
                status_code=429,
                detail="Token issue rate limit exceeded",
                headers={"Retry-After": "60"},
            )
        events.append(now)


def _issue_access_token(subject: str, installation_id: str) -> AccessTokenResponse:
    now = int(time.time())
    expires_at = now + TOKEN_TTL_SECONDS
    payload = {
        "sub": subject,
        "device": hashlib.sha256(installation_id.encode("utf-8")).hexdigest()[:32],
        "jti": secrets.token_urlsafe(18),
        "iat": now,
        "exp": expires_at,
    }
    encoded_payload = _base64url_encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    signature = hmac.new(_signing_secret(), encoded_payload.encode("ascii"), hashlib.sha256).digest()
    return AccessTokenResponse(
        access_token=f"{encoded_payload}.{_base64url_encode(signature)}",
        expires_in=TOKEN_TTL_SECONDS,
    )


def _validate_access_token(token: str) -> AuthenticatedClient:
    try:
        encoded_payload, encoded_signature = token.split(".", maxsplit=1)
        expected_signature = hmac.new(
            _signing_secret(), encoded_payload.encode("ascii"), hashlib.sha256
        ).digest()
        if not hmac.compare_digest(_base64url_decode(encoded_signature), expected_signature):
            raise ValueError("signature")
        payload = json.loads(_base64url_decode(encoded_payload))
        client = AuthenticatedClient(
            subject=str(payload["sub"]),
            installation_id=str(payload["device"]),
            token_id=str(payload["jti"]),
            expires_at=int(payload["exp"]),
        )
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        raise HTTPException(status_code=401, detail="Invalid access token") from None

    if client.expires_at <= int(time.time()):
        raise HTTPException(status_code=401, detail="Access token expired")
    with _auth_lock:
        if client.token_id in _revoked_tokens:
            raise HTTPException(status_code=401, detail="Access token revoked")
    return client


def _enforce_rate_limit(client: AuthenticatedClient, path: str) -> None:
    now = time.monotonic()
    key = f"{client.subject}:{client.installation_id}:{path}"
    with _auth_lock:
        events = _rate_limit_events[key]
        while events and now - events[0] >= 60:
            events.popleft()
        if len(events) >= RATE_LIMIT_PER_MINUTE:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        events.append(now)


def require_api_key(
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> AuthenticatedClient:
    token = _bearer_token(authorization)
    if "." in token:
        client = _validate_access_token(token)
    elif AUTH_MODE == "compat" and API_KEY and hmac.compare_digest(token, API_KEY):
        client = AuthenticatedClient(
            subject="compat-user",
            installation_id="legacy-client",
            token_id="legacy-shared-key",
            expires_at=int(time.time()) + 60,
        )
    else:
        raise HTTPException(status_code=401, detail="Invalid access token")
    _enforce_rate_limit(client, request.url.path)
    return client


@app.post("/v1/auth/token", response_model=AccessTokenResponse)
async def create_access_token(
    payload: AccessTokenRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> AccessTokenResponse:
    try:
        _enforce_token_issue_rate_limit(request)
    except HTTPException:
        _audit_token_issue(
            result="rate_limited",
            request=request,
            installation_id=payload.installation_id,
            app_version=payload.app_version,
        )
        raise

    try:
        credential = _bearer_token(authorization)
    except HTTPException:
        _audit_token_issue(
            result="denied",
            request=request,
            installation_id=payload.installation_id,
            app_version=payload.app_version,
        )
        if TOKEN_FAILURE_DELAY_SECONDS:
            await asyncio.sleep(TOKEN_FAILURE_DELAY_SECONDS)
        raise

    subject = _enrollment_subject(credential)
    if subject is None:
        _audit_token_issue(
            result="denied",
            request=request,
            installation_id=payload.installation_id,
            app_version=payload.app_version,
        )
        if TOKEN_FAILURE_DELAY_SECONDS:
            await asyncio.sleep(TOKEN_FAILURE_DELAY_SECONDS)
        raise HTTPException(status_code=401, detail="Invalid enrollment credential")
    _audit_token_issue(
        result="issued",
        request=request,
        installation_id=payload.installation_id,
        app_version=payload.app_version,
        subject=subject,
    )
    return _issue_access_token(subject, payload.installation_id)


@app.post("/v1/auth/revoke", status_code=204)
async def revoke_access_token(client: AuthenticatedClient = Depends(require_api_key)) -> None:
    if client.token_id == "legacy-shared-key":
        raise HTTPException(status_code=422, detail="Legacy credentials cannot be revoked")
    with _auth_lock:
        _revoked_tokens[client.token_id] = client.expires_at
        _persist_auth_state()


def request_coach_prompt(
    context: Optional[RequestCoachContext],
    fallback_id: str = "body_recomposition",
) -> str:
    profile = get_coach_profile(context.coach_id if context else fallback_id)
    if context is None:
        return profile.prompt()

    return "\n".join(
        [
            f"担当名: {context.coach_name}",
            f"専門領域: {profile.name}",
            f"話し方: {context.coaching_style}",
            f"ユーザーとの約束: {context.promise}",
            f"重点: {', '.join(context.focus_areas) or '記録に応じて判断'}",
            f"進め方: {', '.join(context.approach) or '結論と少数の行動を示す'}",
            f"限界: {', '.join(context.boundaries) or '医療診断をしない'}",
            "共通原則: 最初に結論を示し、入力記録を根拠にし、次の行動は最大3件に絞る。",
            "実在人物を名乗らず、保有していない資格・経歴・医療能力を主張しない。",
        ]
    )


def meal_confirmation_comment(
    context: Optional[RequestCoachContext],
    model_comment: str,
) -> str:
    confirmation = "AIの推定値です。料理名、量、カロリー、PFCを確認して必要なら修正してください。"
    guidance = model_comment.strip()
    if not guidance or guidance == confirmation:
        return confirmation
    coach_name = context.coach_name if context else "担当トレーナー"
    return f"{confirmation} {coach_name}: {guidance}"


@app.get("/v1/health")
async def health(_: None = Depends(require_api_key)) -> dict[str, Any]:
    ollama = await ollama_status()
    calorie_model_available = calorie_clip_runtime.installed
    if not calorie_model_available:
        message = "CalorieCLIPが未導入です。local_llm_server/install_calorie_clip.sh を実行してください。"
    elif not ollama["reachable"]:
        message = "CalorieCLIPは利用できます。料理名・PFCの補助推定にはOllamaを起動してください。"
    elif not ollama["model_available"]:
        message = f"CalorieCLIPは利用できます。Ollamaモデル {OLLAMA_MODEL} は未導入です。"
    else:
        message = "CalorieCLIPと料理情報の補助モデルを利用できます。"

    return {
        "status": "ok",
        "model": "CalorieCLIP",
        "calorie_model_available": calorie_model_available,
        "ollama_reachable": ollama["reachable"],
        "model_available": ollama["model_available"],
        "message": message,
    }


@app.get("/v1/coaches", response_model=list[CoachSummary])
async def coaches(_: None = Depends(require_api_key)) -> list[dict[str, Any]]:
    return [
        {
            "id": profile.id,
            "name": profile.name,
            "identity": profile.identity,
            "priorities": list(profile.priorities),
        }
        for profile in COACH_PROFILES.values()
    ]


@app.get("/v1/evidence/status")
async def evidence_status(_: None = Depends(require_api_key)) -> dict[str, Any]:
    if not EVIDENCE_RAG_ENABLED:
        return {"state": "disabled", "documents": 0, "usable_documents": 0}
    try:
        return evidence_store.status()
    except Exception:
        return {"state": "unavailable", "documents": 0, "usable_documents": 0}


@app.post("/v1/agents/chat", response_model=AgentChatResponse)
async def agent_chat(request: AgentChatRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    coach = get_coach_profile(request.coach_id)
    context_json = json.dumps(request.context, ensure_ascii=False)
    messages_json = json.dumps(
        [message.model_dump() for message in request.recent_messages],
        ensure_ascii=False,
    )
    if len(context_json) + len(messages_json) > 60_000:
        raise HTTPException(status_code=413, detail="AIコンテキストが大きすぎます。集計してから再送してください。")

    evidence_result = None
    evidence_state = "disabled" if not EVIDENCE_RAG_ENABLED else "insufficient"
    if EVIDENCE_RAG_ENABLED:
        try:
            index_status = evidence_store.status()
            if int(index_status.get("usable_documents", 0)) > 0:
                query_vector = None
                if int(index_status.get("vector_chunks", 0)) > 0:
                    query_vector = await ollama_embedding(request.message)
                evidence_result = evidence_store.search(
                    request.message,
                    query_vector=query_vector,
                    limit=5,
                )
                evidence_state = "ready" if evidence_result.citations else "insufficient"
        except Exception:
            evidence_state = "unavailable"

    evidence_context = (
        evidence_result.prompt_context
        if evidence_result is not None and evidence_result.prompt_context
        else "今回の質問に利用できる科学文献はありません。文献を見たふりはしないでください。"
    )
    evidence_instruction = (
        "今回は利用可能な文献があります。一般的な科学的助言には少なくとも1件を使い、"
        "replyの該当文末とevidence_idsの両方に同じIDを入れてください。"
        if evidence_result is not None and evidence_result.citations
        else "今回は利用可能な文献がないため、evidence_idsは空配列にしてください。"
    )

    prompt = f"""
あなたは次の特性を持つパーソナルトレーニングコーチです。
{coach.prompt()}

全コーチ共通の安全ルール:
{chr(10).join(f"- {rule}" for rule in COMMON_SAFETY_RULES)}

ユーザーの質問へ、記録に基づいて日本語で簡潔かつ具体的に回答してください。
入力にない数値や出来事を作らず、不足情報が判断に重要なら質問してください。
context内のmemoriesはユーザーが確認済みの長期記憶として扱ってください。
memory_candidatesには、今後も役立つ安定した目標、好み、制約、習慣のみを最大3件まで候補として返してください。
既存のmemoriesと重複する内容、一時的な状態、推測、診断、写真から推定した身体情報は記憶候補にしないでください。
記憶候補は確定事項ではなく、アプリがユーザーに保存確認するための候補です。

科学文献の扱い:
- 下の「科学文献コンテキスト」は一般的な科学的説明の根拠としてだけ使う
- ユーザー自身の記録と、研究参加者の平均的な知見を混同しない
- 文献の記載を超えた断定、医療診断、因果関係の作り足しをしない
- 数値による推奨は、その数値がユーザー記録または引用する文献本文にある場合だけ使う
- 実際に回答の根拠として使った文献だけ、evidence_idsへE1などのIDを入れる
- 利用可能な文献がない場合はevidence_idsを空にする
- reply内で文献に基づく重要な主張をした場合は、文末に[E1]のようにIDを付ける
{evidence_instruction}

replyの文章ルール:
- 最初に結論を1〜2文で示す
- 内容に応じて2〜4個の短いセクションに分け、セクション間は空行を入れる
- セクション見出しは「【現状】」「【次にやること】」のように単独行で示す
- 複数の根拠は「・」の箇条書き、順序が重要な行動は「1. 」の番号リストにする
- 1段落は2文以内を目安にし、長い一段落を作らない
- 表、深い入れ子、過剰な見出しは使わない
- 不足情報の質問は助言に必要な場合だけ、最後の「### 確認したいこと」に1〜2個まで示す
- Markdown記号は使わず、既存アプリでもそのまま読みやすいプレーンテキストにする
- JSON全体は必ず有効なJSONにする

必ず次のJSONだけを返してください。
{{
  "reply": "結論。\n\n【現状】\n・根拠1\n・根拠2\n\n【次にやること】\n1. 行動1\n2. 行動2",
  "memory_candidates": [
    {{"content": "記憶候補", "reason": "今後の提案に役立つ理由"}}
  ],
  "evidence_ids": ["E1"]
}}

科学文献コンテキスト:
{evidence_context}

最近の会話:
{messages_json}

アプリが生成したコンテキスト:
{context_json}

今回の質問:
{request.message}
""".strip()
    fallback = {
        "reply": "AIトレーナーから回答を取得できませんでした。時間をおいてもう一度お試しください。",
        "memory_candidates": [],
        "evidence_ids": [],
    }
    result = await ollama_json(
        prompt,
        fallback,
        format_schema=agent_chat_json_schema(
            len(evidence_result.citations) if evidence_result is not None else 0
        ),
    )
    normalized = normalize_agent_chat(result, fallback)
    normalized["memory_candidates"] = remove_known_memories(
        normalized["memory_candidates"],
        request.context.get("memories"),
    )
    citations_by_id = {
        f"E{index}": citation
        for index, citation in enumerate(evidence_result.citations, 1)
    } if evidence_result is not None else {}
    normalized["evidence"] = [
        citation_dict(citations_by_id[evidence_id])
        for evidence_id in normalized.pop("evidence_ids", [])
        if evidence_id in citations_by_id
    ]
    normalized["evidence_status"] = {
        "state": evidence_state,
        "confidence": evidence_result.confidence if evidence_result is not None else "insufficient",
        "last_updated_at": evidence_result.last_updated_at if evidence_result is not None else None,
        "searched_documents": evidence_result.searched_documents if evidence_result is not None else 0,
    }
    return normalized


@app.post("/v1/meals/analyze-image", response_model=MealAIDraft)
async def analyze_meal_image(request: MealAnalysisRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    coach_prompt = request_coach_prompt(request.coach)
    prompt = f"""
あなたは食事管理アプリの画像解析AIです。
この食事は次の担当トレーナーの方針に沿って補助してください。
{coach_prompt}

画像から料理名、食材、推定量、カロリー、PFCを推定してください。
画像だけで量は断定できないため、confidenceはlow/medium/highのいずれかにしてください。
commentは最初に確認が必要な点を示し、目的に沿う次の行動を必要な場合だけ1件示してください。
必ず次のJSONだけを返してください。
{{
  "meal_name": "料理名",
  "calories": 0,
  "protein": 0,
  "fat": 0,
  "carbs": 0,
  "confidence": "medium",
  "comment": "ユーザー補正を促す短いコメント",
  "items": [
    {{"name": "食材名", "amount": "150g", "calories": 0, "protein": 0, "fat": 0, "carbs": 0}}
  ]
}}
""".strip()
    fallback = fallback_meal(request)
    result = await ollama_json(
        prompt,
        fallback,
        images=[request.image_base64],
        format_schema=MEAL_DRAFT_JSON_SCHEMA,
    )
    normalized = normalize_meal(result, fallback)
    try:
        image_bytes = base64.b64decode(request.image_base64, validate=True)
        normalized["calories"] = calorie_clip_runtime.predict(image_bytes)
    except Exception as error:
        raise HTTPException(
            status_code=503,
            detail=f"CalorieCLIPで推定できませんでした: {error}",
        ) from error
    normalized["comment"] = meal_confirmation_comment(
        request.coach,
        normalized.get("comment", ""),
    )
    return normalized


@app.post("/v1/meals/analyze-text", response_model=MealAIDraft)
async def analyze_meal_text(
    request: MealTextAnalysisRequest,
    _: None = Depends(require_api_key),
) -> dict[str, Any]:
    items = [item.strip() for item in request.items if item.strip()]
    if not items:
        raise HTTPException(status_code=422, detail="食べたものを1件以上入力してください。")

    coach_prompt = request_coach_prompt(request.coach)
    prompt = f"""
あなたは日本の食事記録アプリの栄養推定補助です。
この食事は次の担当トレーナーの方針に沿って補助してください。
{coach_prompt}

入力された食べたものを1項目ずつ分解し、記載された量または一般的な1食分からカロリーとPFCを推定してください。

ルール:
- 重量や個数が書かれている場合は必ず反映する
- 量がない場合は一般的な1食分を仮定し、amountに仮定量を明記してconfidenceをlowにする
- 商品名だけで特定できない場合や調理油・調味料が不明な場合は控えめに断定しない
- calories、protein、fat、carbsは各品目について0以上の数値にする
- 推定結果はユーザーが修正する下書きであり、commentで量と数値の確認を促す
- 入力にない食品を追加しない
- 必ず指定されたJSON形式だけを返す

食事区分: {request.meal_type}
メモ: {request.memo}
食べたもの:
{json.dumps(items, ensure_ascii=False)}
""".strip()
    fallback = fallback_text_meal(request, items)
    result = await ollama_json(prompt, fallback, format_schema=MEAL_DRAFT_JSON_SCHEMA)
    normalized = normalize_meal(result, fallback)
    normalized["items"] = [
        {
            **item,
            "calories": max(0, item["calories"]),
            "protein": max(0, item["protein"]),
            "fat": max(0, item["fat"]),
            "carbs": max(0, item["carbs"]),
        }
        for item in normalized["items"]
    ]
    normalized["calories"] = sum(item["calories"] for item in normalized["items"])
    normalized["protein"] = sum(item["protein"] for item in normalized["items"])
    normalized["fat"] = sum(item["fat"] for item in normalized["items"])
    normalized["carbs"] = sum(item["carbs"] for item in normalized["items"])
    normalized["meal_name"] = text_meal_name(normalized["items"], fallback["meal_name"])
    normalized["comment"] = meal_confirmation_comment(
        request.coach,
        normalized.get("comment", ""),
    )
    return normalized


@app.post("/v1/body-photos/analyze", response_model=BodyPhotoAIComment)
async def analyze_body_photo(request: BodyPhotoAnalysisRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    prompt = """
あなたはボディメイク管理アプリの写真コメントAIです。
写真だけで体脂肪率や病気を断定しないでください。
同じ条件で撮った写真の変化確認に役立つ、控えめな観察コメントを返してください。
必ず次のJSONだけを返してください。
{
  "summary": "全体の短い要約",
  "abdomen": "腹部の見た目に関するコメント",
  "waist": "脇腹や腹囲まわりの見た目コメント",
  "posture": "姿勢や撮影条件のコメント",
  "score": 0,
  "confidence": "low"
}
""".strip()
    fallback = fallback_body_photo(request)
    result = await ollama_json(prompt, fallback, images=[request.image_base64])
    return normalize_body_photo(result, fallback)


@app.post("/v1/body-photos/analyze-set", response_model=BodyPhotoAIComment)
async def analyze_body_photo_set(
    request: BodyPhotoSetAnalysisRequest,
    _: None = Depends(require_api_key),
) -> dict[str, Any]:
    angle_names = {
        "front": "正面",
        "side": "横",
        "back": "背面",
        "abdomen": "腹部アップ",
    }
    photo_order = "\n".join(
        f"{index + 1}. {angle_names.get(photo.angle, photo.angle)}"
        for index, photo in enumerate(request.photos)
    )
    comparison_order = "\n".join(
        f"{index + 1}. {angle_names.get(photo.angle, photo.angle)}"
        for index, photo in enumerate(request.comparison_photos)
    ) or "なし"
    context = request.context or BodyPhotoAnalysisContext()
    previous_metrics_text = format_body_photo_metrics(context.previous_metrics)
    metric_deltas_text = format_body_photo_metrics(context.metric_deltas, include_sign=True)
    context_text = "\n".join(
        [
            f"目的: {context.profile_goal or '未設定'}",
            f"目標像: {context.outcome_style or '未設定'}",
            f"重点部位: {', '.join(context.focus_areas) or '未設定'}",
            f"経験: {context.experience_level or '未設定'}",
            f"同日の実測値: {', '.join(context.current_metrics) or 'なし'}",
            f"前回の実測値: {previous_metrics_text}",
            f"実測差分（当日 - 前回）: {metric_deltas_text}",
            f"前回撮影日: {context.previous_capture_date or 'なし'}",
            f"前回要約: {context.previous_summary or 'なし'}",
        ]
    )
    coach_prompt = request_coach_prompt(context.coach)
    prompt = f"""
あなたはボディメイク管理アプリの写真コメントAIです。
担当トレーナーとして、次の人物名、話し方、専門方針を一貫して使ってください。
{coach_prompt}

同じ日に撮影した次の複数方向の写真を、1つの撮影セットとして総合的に観察してください。

画像の順番:
{photo_order}

続いて送る前回比較画像の順番:
{comparison_order}

ユーザー文脈:
{context_text}

写真だけで体脂肪率、病気、年齢などを断定しないでください。
各方向で確認できる範囲を区別し、写っていない部位について推測しないでください。
前回比較画像がない場合は、変化した・改善したなどの比較表現を使わないでください。
実測値は写真から推定せず、与えられた値だけを参考情報として扱ってください。
欠測している実測値は推測・補完せず、現在値と前回値が揃っている項目だけを差分比較してください。
結論、目標への意味、良い点、確認できた変化、次の一手の順で、控えめで具体的に返してください。
次の一手は最大3件にしてください。
ユーザーメモ: {request.memo or "なし"}

必ず次のJSONだけを返してください。
{{
  "summary": "複数方向を踏まえた全体の短い要約",
  "abdomen": "正面・横・腹部写真から確認できる腹部のコメント",
  "waist": "正面・横・背面から確認できる脇腹や腹囲まわりのコメント",
  "posture": "複数方向から確認できる姿勢や撮影条件のコメント",
  "score": null,
  "confidence": "low",
  "goal_relevance": "目標との関係",
  "positive_findings": ["確認できた良い点"],
  "observed_changes": ["前回比較画像がある時だけ確認できた変化"],
  "next_actions": ["次に行う具体的な行動"]
}}
""".strip()
    fallback = fallback_body_photo_set(request)
    result = await ollama_json(
        prompt,
        fallback,
        images=[photo.image_base64 for photo in request.photos]
        + [photo.image_base64 for photo in request.comparison_photos],
    )
    return normalize_body_photo(result, fallback)


@app.post("/v1/reports/weekly", response_model=WeeklyReportResponse)
async def weekly_report(request: WeeklyReportRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    coach = get_coach_profile(request.coach_id)
    coach_prompt = request_coach_prompt(request.coach, request.coach_id)
    context = {
        "goal": request.profile_goal,
        "coach": coach.name,
        "experience_level": request.experience_level,
        "body_logs": request.body_logs,
        "meals": request.meals,
        "workouts": request.workouts,
        "body_photos": request.body_photos,
        "sensor_metrics": request.sensor_metrics,
    }
    prompt = f"""
あなたは次の特性を持つパーソナルトレーニングコーチです。
{coach_prompt}

全コーチ共通の安全ルール:
{chr(10).join(f"- {rule}" for rule in COMMON_SAFETY_RULES)}

次の記録をもとに、医療診断ではなく、生活改善とトレーニング調整の観点で週次コメントを作ってください。
経験レベルは {request.experience_level} です。経験に合わない高度または強すぎる提案を避けてください。
入力に存在しない数値や出来事を作らないでください。
最初に今週の結論を示し、良かった点を1つ認めた後、このコーチの優先順位に沿って改善点を判断してください。
入力が足りない項目は不足として明示し、推測で補わないでください。次の行動は最大3件にしてください。
必ず次のJSONだけを返してください。
{{
  "input_summary": "入力データの短い要約",
  "output_comment": "今週の結論",
  "action_suggestion": "次にやることを1から3個の読みやすい文章",
  "good_points": ["記録から確認できる良かった点"],
  "challenges": ["優先して見直す課題"],
  "rationales": ["判断に使った入力記録。入力にない情報は書かない"],
  "next_actions": ["来週実行する具体的な行動。最大3件"]
}}

入力:
{json.dumps(context, ensure_ascii=False)}
""".strip()
    fallback = fallback_weekly(request)
    result = await ollama_json(prompt, fallback)
    return normalize_weekly(result, fallback)


@app.post("/v1/reports/monthly", response_model=WeeklyReportResponse)
async def monthly_report(request: WeeklyReportRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    coach = get_coach_profile(request.coach_id)
    coach_prompt = request_coach_prompt(request.coach, request.coach_id)
    context = {
        "goal": request.profile_goal,
        "coach": coach.name,
        "experience_level": request.experience_level,
        "body_logs": request.body_logs,
        "meals": request.meals,
        "workouts": request.workouts,
        "body_photos": request.body_photos,
        "sensor_metrics": request.sensor_metrics,
    }
    prompt = f"""
あなたは次の特性を持つパーソナルトレーニングコーチです。
{coach_prompt}

全コーチ共通の安全ルール:
{chr(10).join(f"- {rule}" for rule in COMMON_SAFETY_RULES)}

次の直近30日程度の記録をもとに、月次レビュー案を作ってください。
医療診断はせず、入力にない数値や出来事を作らないでください。
前半と後半の変化、設定目標に対する達成状況、継続できた点、見直す一点を分けてください。
翌月目標は1から3件の具体的な候補にし、ユーザー確認前の下書きであることが分かる表現にしてください。
記録が足りず比較できない項目は不足として明示してください。
必ず次のJSONだけを返してください。
{{
  "input_summary": "比較に使った期間・記録と不足情報",
  "output_comment": "月の前半と後半の差、達成状況、良かった点、見直す一点",
  "action_suggestion": "確認後に採用する翌月目標案を1から3件"
}}

入力:
{json.dumps(context, ensure_ascii=False)}
""".strip()
    fallback = fallback_weekly(request)
    fallback["output_comment"] = "30日分の記録を月次レビューとして整理しました。記録が少ない項目は傾向を断定していません。"
    fallback["action_suggestion"] = "翌月目標案です。内容を確認し、無理なく続けられる目標だけ保存してください。"
    result = await ollama_json(prompt, fallback)
    return normalize_weekly(result, fallback)


async def ollama_status() -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.get(f"{OLLAMA_BASE_URL}/api/tags")
            if response.status_code != 200:
                return {"reachable": False, "model_available": False, "models": []}

            models = [
                item.get("name") or item.get("model")
                for item in response.json().get("models", [])
                if isinstance(item, dict)
            ]
            model_available = OLLAMA_MODEL in models
            return {
                "reachable": True,
                "model_available": model_available,
                "models": models,
            }
    except httpx.HTTPError:
        return {"reachable": False, "model_available": False, "models": []}


async def ollama_json(
    prompt: str,
    fallback: dict[str, Any],
    images: Optional[list[str]] = None,
    format_schema: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "format": format_schema or "json",
        "think": False,
    }
    if images:
        payload["images"] = images

    try:
        async with _inference_semaphore:
            async with httpx.AsyncClient(timeout=OLLAMA_REQUEST_TIMEOUT_SECONDS) as client:
                response = await client.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload)
                response.raise_for_status()
            text = response.json().get("response", "")
            parsed = extract_json(text)
            return parsed if isinstance(parsed, dict) else fallback
    except Exception:
        return fallback


async def ollama_embedding(text: str) -> Optional[list[float]]:
    try:
        async with _inference_semaphore:
            async with httpx.AsyncClient(
                timeout=min(OLLAMA_REQUEST_TIMEOUT_SECONDS, 60.0)
            ) as client:
                response = await client.post(
                    f"{OLLAMA_BASE_URL}/api/embed",
                    json={
                        "model": EVIDENCE_EMBEDDING_MODEL,
                        "input": text[:8_000],
                        "truncate": True,
                    },
                )
                response.raise_for_status()
        embeddings = response.json().get("embeddings", [])
        if not embeddings or not isinstance(embeddings[0], list):
            return None
        return [float(value) for value in embeddings[0]]
    except Exception:
        return None


def extract_json(text: str) -> Any:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.DOTALL)
        if not match:
            return {}
        return json.loads(match.group(0))


def normalize_meal(result: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    items = result.get("items") if isinstance(result.get("items"), list) else fallback["items"]
    normalized_items: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        normalized_items.append(
            {
                "name": pick_text(item, "name", "food_name", "食材名", default="不明"),
                "amount": pick_text(item, "amount", "estimated_amount", "量", default="要確認"),
                "calories": pick_float(item, "calories", "calorie", "kcal"),
                "protein": pick_float(item, "protein", "protein_g"),
                "fat": pick_float(item, "fat", "fat_g"),
                "carbs": pick_float(item, "carbs", "carbohydrate", "carbs_g"),
            }
        )

    return {
        "meal_name": pick_text(result, "meal_name", "mealName", "name", "料理名", default=fallback["meal_name"]),
        "calories": pick_float(result, "calories", "calorie", "kcal", default=fallback["calories"]),
        "protein": pick_float(result, "protein", "protein_g", default=fallback["protein"]),
        "fat": pick_float(result, "fat", "fat_g", default=fallback["fat"]),
        "carbs": pick_float(result, "carbs", "carbohydrate", "carbs_g", default=fallback["carbs"]),
        "confidence": pick_text(result, "confidence", "信頼度", default=fallback["confidence"]),
        "comment": pick_text(result, "comment", "note", "コメント", default=fallback["comment"]),
        "items": normalized_items,
    }


def text_meal_name(items: list[dict[str, Any]], fallback: str) -> str:
    names = [
        str(item.get("name", "")).strip()
        for item in items
        if str(item.get("name", "")).strip() not in {"", "不明"}
    ]
    if not names:
        return fallback

    title = "・".join(names[:3])
    if len(names) > 3:
        title += f" ほか{len(names) - 3}品"
    return title


def normalize_body_photo(result: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    return {
        "summary": pick_text(result, "summary", "全体", "要約", default=fallback["summary"]),
        "abdomen": pick_text(result, "abdomen", "腹部", default=fallback["abdomen"]),
        "waist": pick_text(result, "waist", "脇腹", "腹囲", default=fallback["waist"]),
        "posture": pick_text(result, "posture", "姿勢", default=fallback["posture"]),
        "score": pick_optional_float(result, "score", "スコア"),
        "confidence": pick_text(result, "confidence", "信頼度", default=fallback["confidence"]),
        "goal_relevance": pick_text(result, "goal_relevance", "goalRelevance", "目標への意味", default=fallback.get("goal_relevance", "")) or None,
        "positive_findings": pick_string_list(result, "positive_findings", "positiveFindings", "良い点", fallback=fallback.get("positive_findings", [])),
        "observed_changes": pick_string_list(result, "observed_changes", "observedChanges", "確認できた変化", fallback=fallback.get("observed_changes", [])),
        "next_actions": pick_string_list(result, "next_actions", "nextActions", "次の一手", fallback=fallback.get("next_actions", []))[:3],
    }


def format_body_photo_metrics(
    metrics: Optional[BodyPhotoMetricValues],
    *,
    include_sign: bool = False,
) -> str:
    if metrics is None:
        return "なし"

    fields = (
        ("体重", metrics.weight_kg, "kg"),
        ("腹囲", metrics.waist_cm, "cm"),
        ("体脂肪率", metrics.body_fat_percent, "%"),
    )
    values = []
    for label, value, unit in fields:
        if value is None:
            continue
        number = f"{value:+g}" if include_sign else f"{value:g}"
        values.append(f"{label} {number} {unit}")
    return " / ".join(values) or "なし"


def pick_string_list(
    source: dict[str, Any],
    *keys: str,
    fallback: Optional[list[str]] = None,
) -> list[str]:
    for key in keys:
        value = source.get(key)
        if isinstance(value, list):
            items = [str(item).strip() for item in value if str(item).strip()]
            if items:
                return items
        if isinstance(value, str) and value.strip():
            return [line.strip(" -•") for line in value.splitlines() if line.strip(" -•")]
    return list(fallback or [])


def normalize_weekly(result: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    next_actions = pick_string_list(result, "next_actions", "nextActions", "次の行動")[:3]
    action_suggestion = pick_text(
        result,
        "action_suggestion",
        "actionSuggestion",
        "suggestion",
        "改善案",
    )
    if next_actions and not action_suggestion:
        action_suggestion = "\n".join(f"- {item}" for item in next_actions)
    if not action_suggestion:
        action_suggestion = fallback["action_suggestion"]
    return {
        "input_summary": pick_text(result, "input_summary", "inputSummary", "summary", "入力データ要約", default=fallback["input_summary"]),
        "output_comment": pick_text(result, "output_comment", "outputComment", "comment", "コメント", default=fallback["output_comment"]),
        "action_suggestion": action_suggestion,
        "good_points": pick_string_list(result, "good_points", "goodPoints", "良かった点"),
        "challenges": pick_string_list(result, "challenges", "課題", "改善点"),
        "rationales": pick_string_list(result, "rationales", "根拠", "判断の根拠"),
        "next_actions": next_actions,
    }


def normalize_agent_chat(result: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    candidates = result.get("memory_candidates")
    normalized_candidates: list[dict[str, str]] = []
    if isinstance(candidates, list):
        for candidate in candidates[:3]:
            if not isinstance(candidate, dict):
                continue
            content = pick_text(candidate, "content", "memory", "記憶候補")
            reason = pick_text(candidate, "reason", "理由")
            if content and reason:
                normalized_candidates.append({"content": content, "reason": reason})

    reply = pick_text(result, "reply", "response", "answer", "回答", default=fallback["reply"])
    evidence_ids = result.get("evidence_ids")
    if not isinstance(evidence_ids, list):
        evidence_ids = []
    normalized_evidence_ids = []
    for value in evidence_ids:
        evidence_id = str(value).strip().upper()
        if re.fullmatch(r"E[1-8]", evidence_id) and evidence_id not in normalized_evidence_ids:
            normalized_evidence_ids.append(evidence_id)
    return {
        "reply": format_agent_reply(reply),
        "memory_candidates": normalized_candidates,
        "evidence_ids": normalized_evidence_ids,
    }


def format_agent_reply(reply: str) -> str:
    """Keep older app builds readable when a model ignores the Markdown prompt."""
    normalized = reply.replace("\r\n", "\n").replace("\r", "\n").strip()
    if len(normalized) < 140 or "\n" in normalized:
        return normalized

    sentences = [part.strip() for part in re.findall(r".*?[。！？!?](?:[\"'」』】）)]*)|.+$", normalized) if part.strip()]
    if len(sentences) < 2:
        return normalized

    paragraphs: list[str] = []
    current = ""
    for sentence in sentences:
        is_question = sentence.endswith(("？", "?"))
        if is_question:
            if current:
                paragraphs.append(current)
                current = ""
            paragraphs.append(sentence)
        elif not current:
            current = sentence
        elif len(current) + len(sentence) > 100:
            paragraphs.append(current)
            current = sentence
        else:
            current += sentence

    if current:
        paragraphs.append(current)
    return "\n\n".join(paragraphs)


def remove_known_memories(candidates: list[dict[str, str]], memories: Any) -> list[dict[str, str]]:
    if not isinstance(memories, list):
        return candidates

    known: list[str] = []
    for memory in memories:
        if isinstance(memory, str):
            known.append(memory)
        elif isinstance(memory, dict):
            content = pick_text(memory, "content", "memory", "text")
            if content:
                known.append(content)

    return [
        candidate
        for candidate in candidates
        if not any(texts_overlap(candidate["content"], memory) for memory in known)
    ]


def texts_overlap(left: str, right: str) -> bool:
    normalized_left = re.sub(r"[\s、。,.・]", "", left.lower())
    normalized_right = re.sub(r"[\s、。,.・]", "", right.lower())
    if not normalized_left or not normalized_right:
        return False
    if normalized_left in normalized_right or normalized_right in normalized_left:
        return True
    shorter, longer = sorted((normalized_left, normalized_right), key=len)
    window = min(5, len(shorter))
    return window >= 3 and any(
        shorter[index:index + window] in longer
        for index in range(len(shorter) - window + 1)
    )


def pick_text(source: dict[str, Any], *keys: str, default: str = "") -> str:
    for key in keys:
        value = source.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return default


def pick_float(source: dict[str, Any], *keys: str, default: float = 0) -> float:
    value = pick_optional_float(source, *keys)
    return default if value is None else value


def pick_optional_float(source: dict[str, Any], *keys: str) -> Optional[float]:
    for key in keys:
        value = source.get(key)
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            try:
                return float(value)
            except ValueError:
                continue
    return None


def fallback_meal(request: MealAnalysisRequest) -> dict[str, Any]:
    return {
        "meal_name": "AI推定待ちの食事",
        "calories": 0,
        "protein": 0,
        "fat": 0,
        "carbs": 0,
        "confidence": "low",
        "comment": "AI生成結果を下書き化できなかったため、手動補正を前提にした下書きです。",
        "items": [],
    }


def fallback_text_meal(request: MealTextAnalysisRequest, items: list[str]) -> dict[str, Any]:
    return {
        "meal_name": "・".join(items[:3]),
        "calories": 0,
        "protein": 0,
        "fat": 0,
        "carbs": 0,
        "confidence": "low",
        "comment": "栄養値を推定できなかったため、量と数値を手動で入力してください。",
        "items": [
            {
                "name": item,
                "amount": "要確認",
                "calories": 0,
                "protein": 0,
                "fat": 0,
                "carbs": 0,
            }
            for item in items
        ],
    }


def fallback_body_photo(request: BodyPhotoAnalysisRequest) -> dict[str, Any]:
    return {
        "summary": "AI生成結果を下書き化できなかったため、写真メモとして保存してください。",
        "abdomen": "写真だけでは断定できません。同じ条件で撮影した前回写真と比較してください。",
        "waist": "腹囲まわりは測定値と合わせて確認してください。",
        "posture": "同じ角度、同じ光、同じ姿勢で撮ると比較しやすくなります。",
        "score": None,
        "confidence": "low",
    }


def fallback_body_photo_set(request: BodyPhotoSetAnalysisRequest) -> dict[str, Any]:
    angle_count = len({photo.angle for photo in request.photos})
    has_comparison = bool(request.comparison_photos)
    context = request.context or BodyPhotoAnalysisContext()
    return {
        "summary": f"{angle_count}方向の写真を受け取りました。撮影条件を揃えて継続すると比較しやすくなります。",
        "abdomen": "腹部は正面と横の写真を組み合わせ、測定値と合わせて確認してください。",
        "waist": "脇腹や腹囲まわりは複数方向と腹囲の記録を合わせて確認してください。",
        "posture": "同じ角度、同じ光、同じ姿勢で撮ると比較しやすくなります。",
        "score": None,
        "confidence": "low",
        "goal_relevance": f"{context.outcome_style or context.profile_goal}に向けた経過確認として記録できます。" if (context.outcome_style or context.profile_goal) else None,
        "positive_findings": ["複数方向を同じ撮影セットとして記録できています。"],
        "observed_changes": ["前回写真との比較は参考範囲で確認してください。"] if has_comparison else [],
        "next_actions": ["次回も同じ角度、距離、光、姿勢で撮影してください。"],
    }


def fallback_weekly(request: WeeklyReportRequest) -> dict[str, Any]:
    body_count = len(request.body_logs)
    meal_count = len(request.meals)
    workout_count = len(request.workouts)
    photo_count = len(request.body_photos)
    sensor_count = len(request.sensor_metrics)
    return {
        "input_summary": f"身体KPI {body_count}件、食事 {meal_count}件、筋トレ {workout_count}件、体型写真 {photo_count}件、センサー {sensor_count}件を確認しました。",
        "output_comment": "AI生成結果を下書き化できなかったため、記録量にもとづく簡易コメントです。記録は蓄積できています。",
        "action_suggestion": "次は体重・腹囲・食事・筋トレを同じタイミングで記録し、週単位で傾向を確認してください。",
    }
