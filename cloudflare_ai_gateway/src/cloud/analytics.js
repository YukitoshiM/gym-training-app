const RETENTION_SECONDS = 90 * 86_400;
const ALLOWED_CHANNELS = new Set(["app_store", "testflight", "simulator", "unknown"]);
const ALLOWED_EVENTS = new Set([
  "analytics_enabled", "initial_setup_completed", "first_workout_completed",
  "app_opened", "tab_selected", "plan_saved", "workout_completed",
  "body_metric_saved", "meal_saved", "body_photo_saved", "legal_accepted", "tutorial_viewed",
  "daily_recommendation_generated", "daily_recommendation_changed", "daily_action_completed",
  "daily_action_impression", "daily_action_dismissed", "home_primary_action_started",
  "daily_action_reason_opened", "daily_action_replaced", "quick_record_opened",
  "recommendation_source_shown", "notification_opened", "notification_disabled",
  "coach_recommendation_accepted", "coach_selection_changed", "coach_response_helpful",
  "coach_response_needs_improvement", "ai_account_registered", "ai_signup_grant_received",
  "ai_credit_insufficient_shown", "credit_store_opened", "rewarded_ad_started",
  "rewarded_ad_completed", "rewarded_credit_granted", "rewarded_ad_failed",
  "credit_purchase_completed", "credit_purchase_pending", "credit_purchase_cancelled",
  "credit_purchase_failed",
]);
const ALLOWED_PROPERTIES = new Map([
  ["goal", new Set(["diet", "muscleGain", "health", "bodyShape", "performance"])],
  ["experience", new Set(["beginner", "intermediate", "advanced"])],
  ["readiness", new Set(["good", "normal", "tired", "rest"])],
  ["actionCategory", new Set(["workout", "steps", "protein", "mealGuidance", "bodyWeight", "waist", "bodyPhoto", "sleep", "recovery", "lightActivity"])],
  ["fromCategory", new Set(["workout", "steps", "protein", "mealGuidance", "bodyWeight", "waist", "bodyPhoto", "sleep", "recovery", "lightActivity"])],
  ["toCategory", new Set(["workout", "steps", "protein", "mealGuidance", "bodyWeight", "waist", "bodyPhoto", "sleep", "recovery", "lightActivity"])],
  ["source", new Set(["localRule", "ai", "mixed", "user"])],
  ["reason", new Set(["time", "equipment", "fatigue", "pain", "schedule", "already_done", "mismatch", "other"])],
  ["completionMethod", new Set(["manual", "automatic"])],
]);

export async function recordCloudAnalytics(request, env, client) {
  requireDatabase(env);
  const body = await readJSON(request);
  if (!Array.isArray(body?.events) || body.events.length < 1 || body.events.length > 100) {
    throw validationError("events must contain 1 to 100 items");
  }
  const now = Math.floor(Date.now() / 1_000);
  const events = body.events.map((event) => validatedEvent(event, now));
  const cleanup = env.BODYMODE_DB.prepare(
    "DELETE FROM anonymous_events WHERE expires_at < unixepoch()",
  );
  const statements = events.map((event) => env.BODYMODE_DB.prepare(`
    INSERT OR IGNORE INTO anonymous_events(
      event_id, installation_key, event_name, dimension, properties_json,
      app_version, locale, distribution_channel, occurred_at, expires_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    event.id,
    client.installationKey,
    event.name,
    event.dimension,
    JSON.stringify(event.properties),
    event.appVersion,
    event.locale,
    event.channel,
    event.occurredAt,
    event.occurredAt + RETENTION_SECONDS,
  ));
  const results = await env.BODYMODE_DB.batch([cleanup, ...statements]);
  const accepted = results.slice(1).reduce(
    (total, result) => total + Number(result?.meta?.changes || 0),
    0,
  );
  return { accepted };
}

export async function deleteCloudAnalytics(env, client) {
  requireDatabase(env);
  const result = await env.BODYMODE_DB.prepare(
    "DELETE FROM anonymous_events WHERE installation_key = ?",
  ).bind(client.installationKey).run();
  return { deleted: Number(result?.meta?.changes || 0) };
}

function validatedEvent(event, now) {
  const id = String(event?.id || "");
  const occurredAt = Number(event?.occurred_at);
  const name = String(event?.name || "");
  const dimension = event?.dimension == null ? "" : String(event.dimension);
  const appVersion = String(event?.app_version || "");
  const locale = String(event?.locale || "");
  const channel = String(event?.channel || "app_store");
  const properties = event?.properties ?? {};
  if (!/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(id)) {
    throw validationError("invalid event id");
  }
  if (!Number.isInteger(occurredAt) || occurredAt < now - RETENTION_SECONDS || occurredAt > now + 300) {
    throw validationError("invalid event timestamp");
  }
  if (!ALLOWED_EVENTS.has(name) || dimension.length > 40 || appVersion.length > 40 || locale.length > 20) {
    throw validationError("unsupported event metadata");
  }
  if (!ALLOWED_CHANNELS.has(channel) || !isPlainObject(properties)) {
    throw validationError("unsupported event channel or properties");
  }
  for (const [key, value] of Object.entries(properties)) {
    if (key === "position") {
      if (!Number.isInteger(value) || value < 0 || value > 2) throw validationError("invalid position");
      continue;
    }
    if (!ALLOWED_PROPERTIES.get(key)?.has(value)) throw validationError("unsupported event property");
  }
  return { id, occurredAt, name, dimension, properties, appVersion, locale, channel };
}

async function readJSON(request) {
  const contentLength = Number(request.headers.get("content-length") || 0);
  if (contentLength > 128 * 1024) throw validationError("analytics payload too large", 413);
  try {
    return await request.json();
  } catch {
    throw validationError("invalid JSON");
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validationError(message, status = 422) {
  const error = new Error(message);
  error.status = status;
  error.code = status === 413 ? "request_too_large" : "invalid_analytics_event";
  return error;
}

function requireDatabase(env) {
  if (!env.BODYMODE_DB) {
    const error = new Error("cloud_database_not_configured");
    error.status = 503;
    error.code = "cloud_database_not_configured";
    throw error;
  }
}
