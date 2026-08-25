import { requestLunaJSON } from "./openai.js";
import { AI_FEATURE_LIMITS } from "./limits.js";
import { coachDeveloperPrompt } from "./coaches.js";

const LIMITS = AI_FEATURE_LIMITS.mealImage;

export const MEAL_DRAFT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "meal_name",
    "calories",
    "protein",
    "fat",
    "carbs",
    "confidence",
    "comment",
    "items",
  ],
  properties: {
    meal_name: { type: "string" },
    calories: { type: "number", minimum: 0 },
    protein: { type: "number", minimum: 0 },
    fat: { type: "number", minimum: 0 },
    carbs: { type: "number", minimum: 0 },
    confidence: { type: "string", enum: ["low", "medium", "high"] },
    comment: { type: "string" },
    items: {
      type: "array",
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "amount", "calories", "protein", "fat", "carbs"],
        properties: {
          name: { type: "string" },
          amount: { type: "string" },
          calories: { type: "number", minimum: 0 },
          protein: { type: "number", minimum: 0 },
          fat: { type: "number", minimum: 0 },
          carbs: { type: "number", minimum: 0 },
        },
      },
    },
  },
};

export async function analyzeMealImageWithLuna(payload, env, options = {}) {
  const imageBase64 = normalizedImage(payload?.image_base64);
  const locale = normalizedLocale(payload?.locale || payload?.language);
  const mealType = normalizedMealType(payload?.meal_type);
  const memo = String(payload?.memo || "").slice(0, LIMITS.memoCharacters);
  const coachPolicy = coachDeveloperPrompt({
    coachID: payload?.coach?.coach_id,
    coachContext: payload?.coach,
    task: "recognize a meal and provide a user-editable nutrition draft aligned with the user's fitness goal",
  });

  const result = await requestLunaJSON({
    env,
    developerPrompt: [
      coachPolicy,
      "Act as the assigned trainer. Meal recognition supplies an editable factual draft; the comment should use the trainer's priorities and voice.",
      "Identify only food visible in the image or explicitly described by the user.",
      "Estimate portions conservatively and lower confidence when quantity is uncertain.",
      "Nutrition numbers are a draft and will be recalculated from a food composition database.",
      "Do not make medical claims.",
      `Write meal_name, item names, and comment in locale ${locale}.`,
    ].join("\n"),
    userContent: [
      {
        type: "input_text",
        text: JSON.stringify({ meal_type: mealType, memo, locale }),
      },
      {
        type: "input_image",
        image_url: `data:image/jpeg;base64,${imageBase64}`,
        detail: "low",
      },
    ],
    schemaName: "bodymode_meal_draft",
    schema: MEAL_DRAFT_SCHEMA,
    maxInputCharacters: LIMITS.inputCharacters,
    maxOutputTokens: LIMITS.outputTokens,
    fetchImpl: options.fetchImpl,
  });

  return {
    ...result,
    data: normalizeMealDraft(result.data),
  };
}

export async function analyzeMealTextWithLuna(payload, env, options = {}) {
  const locale = normalizedLocale(payload?.locale || payload?.language);
  const mealType = normalizedMealType(payload?.meal_type);
  const memo = String(payload?.memo || "").slice(0, LIMITS.memoCharacters);
  const items = Array.isArray(payload?.items)
    ? payload.items.map((item) => String(item || "").trim()).filter(Boolean).slice(0, 30)
    : [];
  if (!items.length || items.some((item) => item.length > 120)) {
    throw new TypeError("invalid_meal_items");
  }
  const coachPolicy = coachDeveloperPrompt({
    coachID: payload?.coach?.coach_id,
    coachContext: payload?.coach,
    task: "turn listed foods into a user-editable nutrition draft aligned with the user's fitness goal",
  });

  const result = await requestLunaJSON({
    env,
    developerPrompt: [
      coachPolicy,
      "Act as the assigned trainer. Keep nutrition estimates factual and place goal-specific coaching only in comment.",
      "Use only foods explicitly listed by the user.",
      "Use a stated amount when present. Otherwise assume a conservative typical serving and set confidence to low.",
      "Return a user-editable nutrition draft, not a medical conclusion.",
      `Write meal_name, item names, and comment in locale ${locale}.`,
    ].join("\n"),
    userContent: [{
      type: "input_text",
      text: JSON.stringify({ meal_type: mealType, memo, items, locale }),
    }],
    schemaName: "bodymode_meal_text_draft",
    schema: MEAL_DRAFT_SCHEMA,
    maxInputCharacters: LIMITS.inputCharacters,
    maxOutputTokens: LIMITS.outputTokens,
    fetchImpl: options.fetchImpl,
  });
  const normalized = normalizeMealDraft(result.data);
  const totals = normalized.items.reduce((value, item) => ({
    calories: value.calories + item.calories,
    protein: value.protein + item.protein,
    fat: value.fat + item.fat,
    carbs: value.carbs + item.carbs,
  }), { calories: 0, protein: 0, fat: 0, carbs: 0 });
  return { ...result, data: { ...normalized, ...totals } };
}

function normalizedImage(value) {
  const image = String(value || "").trim();
  if (
    !image ||
    image.length > LIMITS.imageBase64Characters ||
    !/^[A-Za-z0-9+/=]+$/.test(image)
  ) {
    throw new TypeError("invalid_image_base64");
  }
  return image;
}

function normalizedLocale(value) {
  const locale = String(value || "en-US").trim();
  return /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(locale) ? locale : "en-US";
}

function normalizedMealType(value) {
  const mealType = String(value || "snack").trim().toLowerCase();
  return new Set(["breakfast", "lunch", "dinner", "snack"]).has(mealType)
    ? mealType
    : "snack";
}

function normalizeMealDraft(draft) {
  const items = Array.isArray(draft?.items) ? draft.items.slice(0, 20) : [];
  return {
    meal_name: String(draft?.meal_name || "Meal").slice(0, 120),
    calories: finiteNonnegative(draft?.calories),
    protein: finiteNonnegative(draft?.protein),
    fat: finiteNonnegative(draft?.fat),
    carbs: finiteNonnegative(draft?.carbs),
    confidence: ["low", "medium", "high"].includes(draft?.confidence)
      ? draft.confidence
      : "low",
    comment: String(draft?.comment || "").slice(0, 300),
    items: items.map((item) => ({
      name: String(item?.name || "Food").slice(0, 120),
      amount: String(item?.amount || "unknown").slice(0, 40),
      calories: finiteNonnegative(item?.calories),
      protein: finiteNonnegative(item?.protein),
      fat: finiteNonnegative(item?.fat),
      carbs: finiteNonnegative(item?.carbs),
    })),
  };
}

function finiteNonnegative(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, number) : 0;
}
