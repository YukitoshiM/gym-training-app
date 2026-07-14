import json
import os
import re
from typing import Any, Optional

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field


APP_NAME = "Gym Training Local LLM"
API_KEY = os.getenv("LOCAL_AI_API_KEY", "dev-local-key")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma4:12b")

app = FastAPI(title=APP_NAME)


class MealAnalysisRequest(BaseModel):
    image_base64: str
    meal_type: str = "lunch"
    memo: str = ""


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


class BodyPhotoAnalysisRequest(BaseModel):
    image_base64: str
    angle: str = "front"
    memo: str = ""


class BodyPhotoAIComment(BaseModel):
    summary: str
    abdomen: str
    waist: str
    posture: str
    score: Optional[float] = None
    confidence: str


class WeeklyReportRequest(BaseModel):
    profile_goal: str
    body_logs: list[str] = []
    meals: list[str] = []
    workouts: list[str] = []
    body_photos: list[str] = []


class WeeklyReportResponse(BaseModel):
    input_summary: str
    output_comment: str
    action_suggestion: str


def require_api_key(authorization: Optional[str] = Header(default=None)) -> None:
    if not API_KEY:
        return
    expected = f"Bearer {API_KEY}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="Invalid API key")


@app.get("/v1/health")
async def health(_: None = Depends(require_api_key)) -> dict[str, Any]:
    ollama = await ollama_status()
    if not ollama["reachable"]:
        message = f"Ollamaに接続できません。Mac miniで `ollama serve` を起動し、OLLAMA_BASE_URL={OLLAMA_BASE_URL} を確認してください。"
    elif not ollama["model_available"]:
        message = f"Ollamaは起動していますが、モデル {OLLAMA_MODEL} が見つかりません。`ollama pull {OLLAMA_MODEL}` を実行するか、OLLAMA_MODELを変更してください。"
    else:
        message = "local_llm_server、Ollama、指定モデルに接続できています。"

    return {
        "status": "ok",
        "model": OLLAMA_MODEL,
        "ollama_reachable": ollama["reachable"],
        "model_available": ollama["model_available"],
        "message": message,
    }


@app.post("/v1/meals/analyze-image", response_model=MealAIDraft)
async def analyze_meal_image(request: MealAnalysisRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    prompt = """
あなたは食事管理アプリの画像解析AIです。
画像から料理名、食材、推定量、カロリー、PFCを推定してください。
画像だけで量は断定できないため、confidenceはlow/medium/highのいずれかにしてください。
必ず次のJSONだけを返してください。
{
  "meal_name": "料理名",
  "calories": 0,
  "protein": 0,
  "fat": 0,
  "carbs": 0,
  "confidence": "medium",
  "comment": "ユーザー補正を促す短いコメント",
  "items": [
    {"name": "食材名", "amount": "150g", "calories": 0, "protein": 0, "fat": 0, "carbs": 0}
  ]
}
""".strip()
    fallback = fallback_meal(request)
    result = await ollama_json(prompt, fallback, images=[request.image_base64])
    return normalize_meal(result, fallback)


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


@app.post("/v1/reports/weekly", response_model=WeeklyReportResponse)
async def weekly_report(request: WeeklyReportRequest, _: None = Depends(require_api_key)) -> dict[str, Any]:
    context = {
        "goal": request.profile_goal,
        "body_logs": request.body_logs,
        "meals": request.meals,
        "workouts": request.workouts,
        "body_photos": request.body_photos,
    }
    prompt = f"""
あなたはAIボディメイクマネージャーです。
次の記録をもとに、医療診断ではなく、生活改善とトレーニング調整の観点で週次コメントを作ってください。
無理な減量や断定表現は避けてください。
必ず次のJSONだけを返してください。
{{
  "input_summary": "入力データの短い要約",
  "output_comment": "現在の状態と良い点/気になる点",
  "action_suggestion": "次にやることを1から3個"
}}

入力:
{json.dumps(context, ensure_ascii=False)}
""".strip()
    fallback = fallback_weekly(request)
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


async def ollama_json(prompt: str, fallback: dict[str, Any], images: Optional[list[str]] = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "think": False,
    }
    if images:
        payload["images"] = images

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload)
            response.raise_for_status()
        text = response.json().get("response", "")
        parsed = extract_json(text)
        return parsed if isinstance(parsed, dict) else fallback
    except Exception:
        return fallback


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


def normalize_body_photo(result: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    return {
        "summary": pick_text(result, "summary", "全体", "要約", default=fallback["summary"]),
        "abdomen": pick_text(result, "abdomen", "腹部", default=fallback["abdomen"]),
        "waist": pick_text(result, "waist", "脇腹", "腹囲", default=fallback["waist"]),
        "posture": pick_text(result, "posture", "姿勢", default=fallback["posture"]),
        "score": pick_optional_float(result, "score", "スコア"),
        "confidence": pick_text(result, "confidence", "信頼度", default=fallback["confidence"]),
    }


def normalize_weekly(result: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    return {
        "input_summary": pick_text(result, "input_summary", "inputSummary", "summary", "入力データ要約", default=fallback["input_summary"]),
        "output_comment": pick_text(result, "output_comment", "outputComment", "comment", "コメント", default=fallback["output_comment"]),
        "action_suggestion": pick_text(result, "action_suggestion", "actionSuggestion", "suggestion", "改善案", default=fallback["action_suggestion"]),
    }


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


def fallback_body_photo(request: BodyPhotoAnalysisRequest) -> dict[str, Any]:
    return {
        "summary": "AI生成結果を下書き化できなかったため、写真メモとして保存してください。",
        "abdomen": "写真だけでは断定できません。同じ条件で撮影した前回写真と比較してください。",
        "waist": "腹囲まわりは測定値と合わせて確認してください。",
        "posture": "同じ角度、同じ光、同じ姿勢で撮ると比較しやすくなります。",
        "score": None,
        "confidence": "low",
    }


def fallback_weekly(request: WeeklyReportRequest) -> dict[str, Any]:
    body_count = len(request.body_logs)
    meal_count = len(request.meals)
    workout_count = len(request.workouts)
    photo_count = len(request.body_photos)
    return {
        "input_summary": f"身体KPI {body_count}件、食事 {meal_count}件、筋トレ {workout_count}件、体型写真 {photo_count}件を確認しました。",
        "output_comment": "AI生成結果を下書き化できなかったため、記録量にもとづく簡易コメントです。記録は蓄積できています。",
        "action_suggestion": "次は体重・腹囲・食事・筋トレを同じタイミングで記録し、週単位で傾向を確認してください。",
    }
