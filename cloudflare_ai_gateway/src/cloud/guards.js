import { cloudFingerprint } from "./auth.js";

export class OperationalGuardError extends Error {
  constructor(code, status, message, retryAfter = 0) {
    super(message);
    this.name = "OperationalGuardError";
    this.code = code;
    this.status = status;
    this.retryAfter = retryAfter;
  }
}

export async function enforcePublicEndpointLimit(request, env, scope, options = {}) {
  if (!env.BODYMODE_DB) return;
  const address = String(request.headers.get("cf-connecting-ip") || "unknown").slice(0, 80);
  const subject = await cloudFingerprint(env, `rate:${scope}:${address}`, 24);
  await enforceWindow(env, scope, subject, options);
}

export async function enforceAuthenticatedLimit(env, client, scope = "authenticated", options = {}) {
  if (!env.BODYMODE_DB) return;
  await enforceWindow(env, scope, client.accountKey, options);
}

export async function enforceAIGenerationGuards(env, client) {
  if (String(env.BODYMODE_AI_ENABLED ?? "1").trim().toLowerCase() === "0" ||
      String(env.BODYMODE_AI_ENABLED ?? "1").trim().toLowerCase() === "false") {
    throw new OperationalGuardError(
      "ai_temporarily_disabled",
      503,
      "AI機能を一時停止しています。手動記録は引き続き利用できます。",
      300,
    );
  }
  await enforceAuthenticatedLimit(env, client, "ai_generation", {
    limit: boundedInteger(env.BODYMODE_AI_REQUESTS_PER_MINUTE, 10, 1, 120),
    windowSeconds: 60,
  });
  if (!env.BODYMODE_DB) return;
  const dayStart = utcDayStart();
  const dailyLimit = boundedInteger(env.BODYMODE_AI_GLOBAL_DAILY_LIMIT, 500, 1, 100_000);
  const result = await env.BODYMODE_DB.prepare(`
    SELECT COUNT(*) AS count
    FROM credit_reservations
    WHERE created_at >= ? AND status IN ('pending', 'completed')
  `).bind(dayStart).first();
  if (Number(result?.count || 0) >= dailyLimit) {
    throw new OperationalGuardError(
      "ai_daily_budget_reached",
      503,
      "本日のAI利用上限に達しました。手動記録は引き続き利用できます。",
      secondsUntilNextUTCDay(),
    );
  }
}

async function enforceWindow(env, scope, subject, options) {
  const limit = boundedInteger(options.limit, 120, 1, 10_000);
  const windowSeconds = boundedInteger(options.windowSeconds, 60, 1, 86_400);
  const now = unixTime();
  const windowStart = Math.floor(now / windowSeconds) * windowSeconds;
  await env.BODYMODE_DB.prepare(`
    INSERT INTO api_rate_windows(
      scope, subject_key, window_started_at, request_count, expires_at
    ) VALUES (?, ?, ?, 1, ?)
    ON CONFLICT(scope, subject_key, window_started_at)
    DO UPDATE SET request_count = request_count + 1
  `).bind(scope, subject, windowStart, windowStart + windowSeconds * 2).run();
  const record = await env.BODYMODE_DB.prepare(`
    SELECT request_count FROM api_rate_windows
    WHERE scope = ? AND subject_key = ? AND window_started_at = ?
  `).bind(scope, subject, windowStart).first();
  if (Number(record?.request_count || 0) > limit) {
    throw new OperationalGuardError(
      "rate_limit_exceeded",
      429,
      "操作が集中しています。少し待ってから再試行してください。",
      Math.max(1, windowStart + windowSeconds - now),
    );
  }
}

function utcDayStart() {
  const now = new Date();
  return Math.floor(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()) / 1_000);
}

function secondsUntilNextUTCDay() {
  const now = Date.now();
  const current = new Date(now);
  const next = Date.UTC(current.getUTCFullYear(), current.getUTCMonth(), current.getUTCDate() + 1);
  return Math.max(60, Math.ceil((next - now) / 1_000));
}

function unixTime() {
  return Math.floor(Date.now() / 1_000);
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(parsed, maximum));
}
