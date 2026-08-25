import {
  completeCreditReservation,
  releaseCreditReservation,
  reserveCredits,
} from "./credits.js";
import { searchCloudEvidence } from "./evidence.js";
import { AI_FEATURE_LIMITS } from "./limits.js";
import { analyzeMealImageWithLuna, analyzeMealTextWithLuna } from "./meal.js";
import { requestLunaJSON } from "./openai.js";
import { enforceAIGenerationGuards } from "./guards.js";
import { coachDeveloperPrompt } from "./coaches.js";

const CHAT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "memory_candidates", "evidence_ids"],
  properties: {
    reply: { type: "string" },
    memory_candidates: {
      type: "array", maxItems: 3,
      items: {
        type: "object", additionalProperties: false,
        required: ["content", "reason"],
        properties: { content: { type: "string" }, reason: { type: "string" } },
      },
    },
    evidence_ids: { type: "array", maxItems: 5, items: { type: "string" } },
  },
};

const MEMORY_CANDIDATES_PROPERTY = {
  type: "array", maxItems: 3,
  items: {
    type: "object", additionalProperties: false,
    required: ["content", "reason"],
    properties: { content: { type: "string" }, reason: { type: "string" } },
  },
};

const EVIDENCE_IDS_PROPERTY = {
  type: "array", maxItems: 5, items: { type: "string", pattern: "^E[1-5]$" },
};

const PLAN_RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["name", "summary", "exercises", "memory_candidates", "evidence_ids"],
  properties: {
    name: { type: "string" },
    summary: { type: "string" },
    exercises: {
      type: "array", minItems: 1, maxItems: 12,
      items: {
        type: "object", additionalProperties: false,
        required: [
          "exercise_name", "sets", "reps", "weight", "rest_seconds", "target_rpe",
          "concentric_seconds", "eccentric_seconds", "tempo_beat_speed",
          "alternative_exercise_names",
        ],
        properties: {
          exercise_name: { type: "string" },
          sets: { type: "integer", minimum: 1, maximum: 10 },
          reps: { type: "integer", minimum: 1, maximum: 100 },
          weight: { type: ["number", "null"], minimum: -500, maximum: 1_000 },
          rest_seconds: { type: "integer", minimum: 5, maximum: 900 },
          target_rpe: { type: "number", minimum: 1, maximum: 10 },
          concentric_seconds: { type: "integer", minimum: 1, maximum: 10 },
          eccentric_seconds: { type: "integer", minimum: 1, maximum: 10 },
          tempo_beat_speed: { type: "integer", minimum: 1, maximum: 3 },
          alternative_exercise_names: {
            type: "array", maxItems: 3, items: { type: "string" },
          },
        },
      },
    },
    memory_candidates: MEMORY_CANDIDATES_PROPERTY,
    evidence_ids: EVIDENCE_IDS_PROPERTY,
  },
};

const DAILY_RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "keep_existing", "readiness_level", "summary", "change_reason", "actions",
    "memory_candidates", "evidence_ids",
  ],
  properties: {
    keep_existing: { type: "boolean" },
    readiness_level: { type: ["string", "null"], enum: ["good", "normal", "tired", "rest", null] },
    summary: { type: "string" },
    change_reason: { type: "string" },
    actions: {
      type: "array", maxItems: 3,
      items: {
        type: "object", additionalProperties: false,
        required: ["id", "category", "title", "target", "rationale"],
        properties: {
          id: { type: ["string", "null"] },
          category: {
            type: "string",
            enum: [
              "workout", "steps", "protein", "mealGuidance", "bodyWeight", "waist",
              "bodyPhoto", "sleep", "recovery", "lightActivity",
            ],
          },
          title: { type: "string" },
          target: { type: ["number", "null"] },
          rationale: { type: "string" },
        },
      },
    },
    memory_candidates: MEMORY_CANDIDATES_PROPERTY,
    evidence_ids: EVIDENCE_IDS_PROPERTY,
  },
};

const BODY_PHOTO_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "summary", "abdomen", "waist", "posture", "score", "confidence",
    "goal_relevance", "positive_findings", "observed_changes", "next_actions",
    "reference_estimates",
  ],
  properties: {
    summary: { type: "string" }, abdomen: { type: "string" }, waist: { type: "string" },
    posture: { type: "string" }, score: { type: ["number", "null"], minimum: 0, maximum: 100 },
    confidence: { type: "string", enum: ["low", "medium", "high"] },
    goal_relevance: { type: ["string", "null"] },
    positive_findings: { type: "array", maxItems: 4, items: { type: "string" } },
    observed_changes: { type: "array", maxItems: 4, items: { type: "string" } },
    next_actions: { type: "array", maxItems: 3, items: { type: "string" } },
    reference_estimates: {
      type: "array", maxItems: 3,
      items: {
        type: "object", additionalProperties: false,
        required: ["metric", "lower_bound", "upper_bound", "unit", "confidence", "rationale"],
        properties: {
          metric: { type: "string" }, lower_bound: { type: "number" }, upper_bound: { type: "number" },
          unit: { type: "string" }, confidence: { type: "string", enum: ["low", "medium"] },
          rationale: { type: "string" },
        },
      },
    },
  },
};

const REPORT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "input_summary", "output_comment", "action_suggestion", "good_points",
    "challenges", "rationales", "next_actions",
  ],
  properties: {
    input_summary: { type: "string" }, output_comment: { type: "string" },
    action_suggestion: { type: "string" },
    good_points: { type: "array", maxItems: 4, items: { type: "string" } },
    challenges: { type: "array", maxItems: 4, items: { type: "string" } },
    rationales: { type: "array", maxItems: 4, items: { type: "string" } },
    next_actions: { type: "array", maxItems: 3, items: { type: "string" } },
  },
};

export async function runCloudGenerationRoute(request, env, client, url) {
  const payload = await readJSON(request);
  const requestID = request.headers.get("x-request-id") || crypto.randomUUID();
  if (url.pathname === "/v1/meals/analyze-image") {
    return runMetered(env, client, "meal", requestID, () => analyzeMealImageWithLuna(payload, env));
  }
  if (url.pathname === "/v1/meals/analyze-text") {
    return runMetered(env, client, "meal", requestID, () => analyzeMealTextWithLuna(payload, env));
  }
  if (url.pathname === "/v1/body-photos/analyze" || url.pathname === "/v1/body-photos/analyze-set") {
    return runMetered(env, client, "body_photo", requestID, () => analyzeBodyPhotos(payload, env, url.pathname));
  }
  if (url.pathname === "/v1/agents/chat") {
    const feature = chatFeature(payload?.purpose);
    return runMetered(env, client, feature, requestID, () => runCoachChat(payload, env));
  }
  if (url.pathname === "/v1/reports/weekly" || url.pathname === "/v1/reports/monthly") {
    const monthly = url.pathname.endsWith("/monthly");
    return runMetered(env, client, monthly ? "monthly_report" : "weekly_report", requestID, () => runReport(payload, env, monthly));
  }
  return null;
}

async function runMetered(env, client, feature, requestID, operation) {
  await enforceAIGenerationGuards(env, client);
  const reservation = await reserveCredits(env, client, feature, requestID);
  const started = Date.now();
  try {
    const result = await operation();
    await completeCreditReservation(env, reservation, {
      model: result.model,
      inputTokens: result.usage?.inputTokens,
      outputTokens: result.usage?.outputTokens,
      durationMS: Date.now() - started,
    });
    return result.data;
  } catch (error) {
    await releaseCreditReservation(env, reservation, String(error?.code || error?.name || "ai_failed"));
    throw error;
  }
}

async function runCoachChat(payload, env) {
  const purpose = ["chat", "plan_generation", "daily_recommendation"].includes(payload?.purpose)
    ? payload.purpose : "chat";
  const limits = AI_FEATURE_LIMITS[purpose === "chat" ? "chat" : purpose === "plan_generation" ? "planGeneration" : "dailyRecommendation"];
  const message = String(payload?.message || "").trim();
  const maximumMessage = purpose === "chat" ? limits.userMessageCharacters : limits.generatedMessageCharacters;
  if (!message || message.length > maximumMessage) throw validationError("invalid_chat_message");
  const context = plainObject(payload?.context) ? payload.context : {};
  const responseLocale = normalizedResponseLocale(payload?.response_locale || payload?.locale);
  const recentMessages = Array.isArray(payload?.recent_messages) ? payload.recent_messages.slice(-20) : [];
  const coachContext = plainObject(payload?.coach) ? payload.coach : null;
  const coachPolicy = coachDeveloperPrompt({
    coachID: payload?.coach_id,
    coachContext,
    legacyPreferences: Array.isArray(context?.preferences) ? context.preferences : [],
    task: purpose === "plan_generation"
      ? "create an editable training-plan draft"
      : purpose === "daily_recommendation"
        ? "review today's local recommendation using the user's records"
        : "answer the user's in-scope coaching question",
  });
  const input = JSON.stringify({
    coach_id: String(payload?.coach_id || "wellness").slice(0, 60),
    purpose,
    response_locale: responseLocale,
    message,
    context,
    recent_messages: recentMessages.map((item) => ({
      role: item?.role === "assistant" ? "assistant" : "user",
      content: String(item?.content || "").slice(0, 1_000),
    })),
  });
  if (input.length > limits.inputCharacters) throw sizeError();

  const evidence = await searchCloudEvidence(message, env, { limit: 5 });
  const knownMemories = new Set((Array.isArray(context.memories) ? context.memories : [])
    .map((value) => normalizedMemory(value)));
  const structuredPurpose = purpose === "plan_generation" || purpose === "daily_recommendation";
  const result = await requestLunaJSON({
    env,
    developerPrompt: [
      coachPolicy,
      "Lead with a short conclusion, then explain the user's current situation and at most three concrete next actions.",
      "Use only supplied records. Ask at most two short questions when essential information is missing.",
      "Do not diagnose, prescribe treatment, guarantee results, or invent measurements.",
      `Write all user-facing text in locale ${responseLocale}.`,
      "memory_candidates may contain only stable preferences, goals, constraints, or habits not already in memories.",
      "Use evidence only for general claims. Cite used evidence with [E1] in reply and include E1 in evidence_ids.",
      "If evidence is unavailable, evidence_ids must be empty and no citation may be invented.",
      purpose === "plan_generation"
        ? "Return a complete editable plan. Use only exact exercise names allowed by the user message. Do not make the user assemble it."
        : purpose === "daily_recommendation"
          ? "Keep the local actions unless an important record justifies a change. Lead each title with the concrete action and keep rationale to one friendly sentence."
          : "Return the coaching response in reply.",
      `Scientific evidence:\n${evidence.promptContext}`,
    ].join("\n"),
    userContent: [{ type: "input_text", text: input }],
    schemaName: purpose === "plan_generation"
      ? "bodymode_training_plan"
      : purpose === "daily_recommendation"
        ? "bodymode_daily_recommendation"
        : "bodymode_coach_reply",
    schema: purpose === "plan_generation"
      ? PLAN_RESPONSE_SCHEMA
      : purpose === "daily_recommendation"
        ? DAILY_RESPONSE_SCHEMA
        : CHAT_SCHEMA,
    maxInputCharacters: limits.inputCharacters,
    maxOutputTokens: limits.outputTokens,
  });
  const selected = new Set(result.data.evidence_ids || []);
  const citations = evidence.citations.filter((_citation, index) => selected.has(`E${index + 1}`));
  const memoryCandidates = (result.data.memory_candidates || []).filter((candidate) => {
    const key = normalizedMemory(candidate?.content);
    return key && !knownMemories.has(key);
  }).slice(0, 3);
  const reply = structuredPurpose
    ? JSON.stringify(normalizeStructuredReply(result.data, purpose))
    : String(result.data.reply || "").slice(0, 8_000);
  return {
    ...result,
    data: {
      reply,
      memory_candidates: memoryCandidates,
      evidence: citations,
      evidence_status: {
        state: evidence.state,
        confidence: evidence.confidence,
        last_updated_at: evidence.lastUpdatedAt,
        searched_documents: evidence.searchedDocuments,
        matched_documents: evidence.matchedDocuments,
        reason: evidence.reason,
      },
    },
  };
}

function normalizeStructuredReply(data, purpose) {
  if (purpose === "plan_generation") {
    return {
      name: String(data?.name || "BodyMode Plan").slice(0, 40),
      summary: String(data?.summary || "").slice(0, 500),
      exercises: (Array.isArray(data?.exercises) ? data.exercises : []).slice(0, 12).map((item) => ({
        exercise_name: String(item?.exercise_name || "").slice(0, 100),
        sets: boundedNumber(item?.sets, 1, 10, 3, true),
        reps: boundedNumber(item?.reps, 1, 100, 10, true),
        weight: item?.weight == null ? null : boundedNumber(item.weight, -500, 1_000, 0),
        rest_seconds: boundedNumber(item?.rest_seconds, 5, 900, 90, true),
        target_rpe: boundedNumber(item?.target_rpe, 1, 10, 7),
        concentric_seconds: boundedNumber(item?.concentric_seconds, 1, 10, 1, true),
        eccentric_seconds: boundedNumber(item?.eccentric_seconds, 1, 10, 2, true),
        tempo_beat_speed: boundedNumber(item?.tempo_beat_speed, 1, 3, 1, true),
        alternative_exercise_names: stringList(item?.alternative_exercise_names, 3),
      })).filter((item) => item.exercise_name),
    };
  }
  const actions = (Array.isArray(data?.actions) ? data.actions : []).slice(0, 3).map((item) => {
    const action = {
      category: item.category,
      title: String(item?.title || "").slice(0, 80),
      target: item?.target == null ? null : Number(item.target),
      rationale: String(item?.rationale || "").slice(0, 240),
    };
    if (/^[0-9a-fA-F-]{36}$/.test(String(item?.id || ""))) action.id = String(item.id).toLowerCase();
    return action;
  }).filter((item) => item.title);
  const keepExisting = Boolean(data?.keep_existing) || actions.length === 0;
  return {
    keep_existing: keepExisting,
    readiness_level: ["good", "normal", "tired", "rest"].includes(data?.readiness_level)
      ? data.readiness_level : null,
    summary: String(data?.summary || "").slice(0, 240),
    change_reason: keepExisting ? "" : String(data?.change_reason || "").slice(0, 240),
    actions: keepExisting && actions.length === 0 ? [] : actions,
  };
}

async function analyzeBodyPhotos(payload, env, path) {
  const limit = AI_FEATURE_LIMITS.bodyPhoto;
  const memo = String(payload?.memo || "").slice(0, limit.memoCharacters);
  const sourcePhotos = path.endsWith("analyze-set")
    ? [...validatedPhotos(payload?.photos, limit), ...validatedPhotos(payload?.comparison_photos, limit)]
    : [{ image_base64: validatedImage(payload?.image_base64, limit), angle: String(payload?.angle || "front") }];
  if (!sourcePhotos.length || sourcePhotos.length > limit.maximumImages * 2) throw validationError("invalid_body_photos");
  const context = plainObject(payload?.context) ? payload.context : {};
  const coachPolicy = coachDeveloperPrompt({
    coachID: context?.coach?.coach_id,
    coachContext: plainObject(context?.coach) ? context.coach : null,
    task: "assess progress photos against the user's stated goal and available measurements",
  });
  const responseLocale = normalizedResponseLocale(payload?.response_locale || payload?.locale);
  const content = [{
    type: "input_text",
    text: JSON.stringify({ memo, context, response_locale: responseLocale, angles: sourcePhotos.map((photo) => photo.angle), comparison_start: path.endsWith("analyze-set") ? (payload?.photos || []).length : null }),
  }, ...sourcePhotos.map((photo) => ({
    type: "input_image", image_url: `data:image/jpeg;base64,${photo.image_base64}`, detail: "low",
  }))];
  const result = await requestLunaJSON({
    env,
    developerPrompt: [
      coachPolicy,
      "Act as the assigned trainer. Progress-photo observation is one source of evidence for a goal-directed coaching assessment, not the role itself.",
      "Lead summary with the useful conclusion for the user's goal: visible progress, no clear visible change, a possible concern to monitor, or insufficient comparability.",
      "Describe only visible, non-sensitive changes and photography conditions.",
      "Never identify the person, diagnose health, or claim an exact body-fat percentage.",
      "Reference estimates must be conservative ranges with low or medium confidence and are optional guidance.",
      "If comparison photos are supplied, compare matching angles and avoid claims unsupported by the images.",
      "Use supplied measurements only as recorded facts. Explain whether photo observations and measurement trends agree, conflict, or remain inconclusive.",
      "For hypertrophy, connect the assessment to body-weight trend, target-area appearance, progressive overload, nutrition, and recovery when those records are supplied; never infer muscle gain from appearance alone.",
      "positive_findings must contain only favorable progress or goal-supporting behavior. Do not praise the existence, number, or angles of photos.",
      "observed_changes must be concrete and angle-specific when possible. Do not restate every supplied metric as a visual finding.",
      "next_actions must be at most three goal-specific coaching actions. Suggest photography setup only when comparability materially blocks the assessment.",
      `Write all user-facing text in locale ${responseLocale}.`,
    ].join("\n"),
    userContent: content,
    schemaName: "bodymode_photo_observation",
    schema: BODY_PHOTO_SCHEMA,
    maxInputCharacters: limit.inputCharacters,
    maxOutputTokens: limit.outputTokens,
  });
  return { ...result, data: normalizeBodyResult(result.data) };
}

async function runReport(payload, env, monthly) {
  const limits = AI_FEATURE_LIMITS[monthly ? "monthlyReport" : "weeklyReport"];
  const responseLocale = normalizedResponseLocale(payload?.response_locale || payload?.locale);
  const coachPolicy = coachDeveloperPrompt({
    coachID: payload?.coach_id,
    coachContext: plainObject(payload?.coach) ? payload.coach : null,
    task: `create the user's ${monthly ? "monthly" : "weekly"} BodyMode coaching review`,
  });
  const input = JSON.stringify(compactReportPayload(payload));
  if (input.length > limits.inputCharacters) throw sizeError();
  const result = await requestLunaJSON({
    env,
    developerPrompt: [
      coachPolicy,
      `Create a ${monthly ? "monthly" : "weekly"} BodyMode coaching review as the assigned trainer.`,
      "Lead with the conclusion, recognize one positive behavior, then give at most three concrete next actions.",
      "Use only supplied records, explicitly note important missing data, and do not invent trends.",
      "Do not make medical diagnoses or guarantee outcomes.",
      `Write all user-facing text in locale ${responseLocale}.`,
    ].join("\n"),
    userContent: [{ type: "input_text", text: input }],
    schemaName: monthly ? "bodymode_monthly_report" : "bodymode_weekly_report",
    schema: REPORT_SCHEMA,
    maxInputCharacters: limits.inputCharacters,
    maxOutputTokens: limits.outputTokens,
  });
  return { ...result, data: normalizeReport(result.data) };
}

async function readJSON(request) {
  const length = Number(request.headers.get("content-length") || 0);
  if (length > 12 * 1024 * 1024) throw sizeError();
  try { return await request.json(); } catch { throw validationError("invalid_json"); }
}

function validatedPhotos(value, limits) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, limits.maximumImages).map((photo) => ({
    image_base64: validatedImage(photo?.image_base64, limits),
    angle: String(photo?.angle || "front").slice(0, 40),
  }));
}

function validatedImage(value, limits) {
  const image = String(value || "").trim();
  if (!image || image.length > limits.imageBase64Characters || !/^[A-Za-z0-9+/=]+$/.test(image)) {
    throw validationError("invalid_image_base64");
  }
  return image;
}

function compactReportPayload(payload) {
  const list = (value, maximum = 80) => Array.isArray(value)
    ? value.slice(-maximum).map((item) => String(item || "").slice(0, 500)) : [];
  return {
    profile_goal: String(payload?.profile_goal || "").slice(0, 500),
    coach_id: String(payload?.coach_id || "wellness").slice(0, 60),
    coach: plainObject(payload?.coach) ? payload.coach : null,
    experience_level: String(payload?.experience_level || "beginner").slice(0, 40),
    response_locale: normalizedResponseLocale(payload?.response_locale || payload?.locale),
    body_logs: list(payload?.body_logs), meals: list(payload?.meals), workouts: list(payload?.workouts),
    body_photos: list(payload?.body_photos), sensor_metrics: list(payload?.sensor_metrics),
  };
}

function normalizeBodyResult(value) {
  return {
    summary: String(value?.summary || "").slice(0, 1_000),
    abdomen: String(value?.abdomen || "").slice(0, 600),
    waist: String(value?.waist || "").slice(0, 600),
    posture: String(value?.posture || "").slice(0, 600),
    score: Number.isFinite(value?.score) ? Math.max(0, Math.min(value.score, 100)) : null,
    confidence: ["low", "medium", "high"].includes(value?.confidence) ? value.confidence : "low",
    goal_relevance: value?.goal_relevance == null ? null : String(value.goal_relevance).slice(0, 500),
    positive_findings: stringList(value?.positive_findings, 4),
    observed_changes: stringList(value?.observed_changes, 4),
    next_actions: stringList(value?.next_actions, 3),
    reference_estimates: (Array.isArray(value?.reference_estimates) ? value.reference_estimates : []).slice(0, 3),
  };
}

function normalizeReport(value) {
  return {
    input_summary: String(value?.input_summary || "").slice(0, 1_500),
    output_comment: String(value?.output_comment || "").slice(0, 2_000),
    action_suggestion: String(value?.action_suggestion || "").slice(0, 1_500),
    good_points: stringList(value?.good_points, 4), challenges: stringList(value?.challenges, 4),
    rationales: stringList(value?.rationales, 4), next_actions: stringList(value?.next_actions, 3),
  };
}

function stringList(value, maximum) {
  return (Array.isArray(value) ? value : []).slice(0, maximum).map((item) => String(item || "").slice(0, 500));
}

function boundedNumber(value, minimum, maximum, fallback, integer = false) {
  const parsed = Number(value);
  const bounded = Number.isFinite(parsed) ? Math.max(minimum, Math.min(parsed, maximum)) : fallback;
  return integer ? Math.round(bounded) : bounded;
}

function chatFeature(purpose) {
  return purpose === "plan_generation" || purpose === "daily_recommendation" ? purpose : "chat";
}

function normalizedMemory(value) {
  return String(value || "").trim().toLocaleLowerCase().replace(/\s+/g, " ");
}

function normalizedResponseLocale(value) {
  const locale = String(value || "en-US").trim();
  return /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(locale) ? locale : "en-US";
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validationError(code) {
  const error = new Error(code); error.status = 422; error.code = code; return error;
}

function sizeError() {
  const error = new Error("input_limit_exceeded"); error.status = 413; error.code = "input_limit_exceeded"; return error;
}
