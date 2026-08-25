import { authenticateCloudRequest } from "./auth.js";
import { recordCloudAnalytics, deleteCloudAnalytics } from "./analytics.js";
import { cloudCoaches } from "./coaches.js";
import { claimSignupCredits, creditHistory, creditSummary } from "./credits.js";
import { cloudEvidenceStatus } from "./evidence.js";
import { runCloudGenerationRoute } from "./generation.js";
import {
  createAppleSession,
  createEnrollmentSession,
  deleteCloudAccount,
  revokeCloudSession,
} from "./sessions.js";
import { receiveAppStoreNotification, verifyCreditPurchase } from "./purchases.js";
import {
  claimRewardedAd,
  createRewardedAdChallenge,
  verifyRewardedAdCallback,
} from "./rewarded-ads.js";
import { enforceAuthenticatedLimit, enforcePublicEndpointLimit } from "./guards.js";
import { cloudOperationsStatus } from "./operations.js";
import { probeOpenAIModel } from "./openai.js";
import { grantSupportCredits } from "./support.js";

const SUPPORTED_CLOUD_ROUTES = new Set([
  "/v1/health",
  "/v1/auth/token",
  "/v1/auth/revoke",
  "/v1/account/apple",
  "/v1/account",
  "/v1/coaches",
  "/v1/evidence/status",
  "/v1/analytics/events",
  "/v1/usage",
  "/v1/credits",
  "/v1/credits/history",
  "/v1/credits/signup-grant",
  "/v1/credits/rewarded-ad/challenge",
  "/v1/credits/rewarded-ad/claim",
  "/v1/credits/rewarded-ad/ssv",
  "/v1/agents/chat",
  "/v1/meals/analyze-image",
  "/v1/meals/analyze-text",
  "/v1/body-photos/analyze",
  "/v1/body-photos/analyze-set",
  "/v1/reports/weekly",
  "/v1/reports/monthly",
  "/v1/credits/purchases/verify",
  "/v1/app-store/notifications",
  "/v1/operations/status",
  "/v1/operations/credits/grant",
]);

export async function handleCloudRoute(request, env, suppliedURL) {
  const url = suppliedURL || new URL(request.url);
  const routes = configuredCloudRoutes(env);
  if (!routes.has(url.pathname)) return null;

  if (!SUPPORTED_CLOUD_ROUTES.has(url.pathname)) {
    return jsonError(
      503,
      {
        code: "cloud_route_not_ready",
        message: "このAI機能のクラウド移行を準備中です。時間をおいて再試行してください。",
      },
      { "Retry-After": "30" },
    );
  }

  try {
    if (url.pathname === "/v1/health" && request.method === "GET") {
      return await cloudHealth(env);
    }
    if (url.pathname === "/v1/auth/token" && request.method === "POST") {
      await enforcePublicEndpointLimit(request, env, "auth_token", { limit: 10, windowSeconds: 600 });
      return cloudJSON(await createEnrollmentSession(request, env));
    }
    if (url.pathname === "/v1/account/apple" && request.method === "POST") {
      await enforcePublicEndpointLimit(request, env, "apple_account", { limit: 10, windowSeconds: 600 });
      return cloudJSON(await createAppleSession(request, env));
    }
    if (url.pathname === "/v1/app-store/notifications" && request.method === "POST") {
      return cloudJSON(await receiveAppStoreNotification(request, env));
    }
    if (url.pathname === "/v1/credits/rewarded-ad/ssv" && request.method === "GET") {
      await enforcePublicEndpointLimit(request, env, "rewarded_ssv", { limit: 120, windowSeconds: 60 });
      return cloudJSON(await verifyRewardedAdCallback(request, env));
    }

    const client = await authenticateCloudRequest(request, env);
    await enforceAuthenticatedLimit(env, client, "authenticated", { limit: 120, windowSeconds: 60 });
    if (url.pathname === "/v1/auth/revoke" && request.method === "POST") {
      await revokeCloudSession(env, client);
      return new Response(null, { status: 204, headers: cloudHeaders() });
    }
    if (url.pathname === "/v1/account" && request.method === "DELETE") {
      return cloudJSON(await deleteCloudAccount(env, client));
    }
    if (url.pathname === "/v1/credits/purchases/verify" && request.method === "POST") {
      return cloudJSON(await verifyCreditPurchase(request, env, client));
    }
    if (url.pathname === "/v1/coaches" && request.method === "GET") {
      return cloudJSON(cloudCoaches());
    }
    if (url.pathname === "/v1/evidence/status" && request.method === "GET") {
      return cloudJSON(await cloudEvidenceStatus(env));
    }
    if (url.pathname === "/v1/analytics/events" && request.method === "POST") {
      return cloudJSON(await recordCloudAnalytics(request, env, client));
    }
    if (url.pathname === "/v1/analytics/events" && request.method === "DELETE") {
      return cloudJSON(await deleteCloudAnalytics(env, client));
    }
    if (url.pathname === "/v1/credits" && request.method === "GET") {
      return cloudJSON(await creditSummary(env, client));
    }
    if (url.pathname === "/v1/credits/history" && request.method === "GET") {
      return cloudJSON(await creditHistory(env, client, url.searchParams.get("limit")));
    }
    if (url.pathname === "/v1/credits/signup-grant" && request.method === "POST") {
      return cloudJSON(await claimSignupCredits(env, client));
    }
    if (url.pathname === "/v1/credits/rewarded-ad/challenge" && request.method === "POST") {
      return cloudJSON(await createRewardedAdChallenge(env, client));
    }
    if (url.pathname === "/v1/credits/rewarded-ad/claim" && request.method === "POST") {
      return cloudJSON(await claimRewardedAd(env, client, request));
    }
    if (url.pathname === "/v1/usage" && request.method === "GET") {
      return cloudJSON({
        generated_at: new Date().toISOString(),
        enforced: false,
        features: [],
        distribution_channel: distributionChannel(request),
        credits: await creditSummary(env, client),
      });
    }
    if (url.pathname === "/v1/operations/status" && request.method === "GET") {
      return cloudJSON(await cloudOperationsStatus(env, client));
    }
    if (url.pathname === "/v1/operations/credits/grant" && request.method === "POST") {
      return cloudJSON(await grantSupportCredits(request, env, client));
    }
    const generation = await runCloudGenerationRoute(request, env, client, url);
    if (generation) return cloudJSON(generation);
  } catch (error) {
    const status = Number(error?.status || 503);
    const code = String(error?.code || "cloud_service_unavailable");
    const detail = { code, message: publicErrorMessage(error), ...(error?.details || {}) };
    const headers = Number(error?.retryAfter || 0) > 0
      ? { "Retry-After": String(error.retryAfter) }
      : {};
    if (status >= 500) {
      console.error(JSON.stringify({
        event: "cloud_request_failed",
        route: url.pathname,
        method: request.method,
        status,
        code,
        request_id: String(request.headers.get("x-request-id") || "").slice(0, 80),
      }));
    }
    return jsonError(status, detail, headers);
  }

  return null;
}

function cloudJSON(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: cloudHeaders(),
  });
}

export function configuredCloudRoutes(env) {
  return new Set(
    String(env.BODYMODE_CLOUD_ROUTES || "")
      .split(",")
      .map((route) => route.trim())
      .filter(Boolean),
  );
}

async function cloudHealth(env) {
  const model = String(env.BODYMODE_OPENAI_MODEL || "gpt-5.6-luna").trim();
  const modelAllowed = /^gpt-5\.6-luna(?:-|$)/.test(model);
  const providerProbe = await probeOpenAIModel({ env });
  let databaseAvailable = false;
  let schemaVersion = null;
  if (env.BODYMODE_DB) {
    try {
      const schema = await env.BODYMODE_DB.prepare(
        "SELECT value FROM schema_metadata WHERE key = 'schema_version'",
      ).first();
      schemaVersion = schema?.value == null ? null : String(schema.value);
      databaseAvailable = Number.parseInt(schemaVersion || "0", 10) >= 5;
    } catch {
      databaseAvailable = false;
    }
  }
  const aiEnabled = !["0", "false"].includes(String(env.BODYMODE_AI_ENABLED ?? "1").toLowerCase());
  const ready = providerProbe.modelAvailable && modelAllowed && databaseAvailable && aiEnabled;

  return new Response(
    JSON.stringify({
      status: ready ? "ok" : "degraded",
      model,
      provider: "openai",
      runtime: "cloudflare",
      provider_configured: providerProbe.configured,
      provider_reachable: providerProbe.reachable,
      provider_authenticated: providerProbe.authenticated,
      provider_probe_status: providerProbe.status,
      calorie_model_available: ready,
      ollama_reachable: false,
      model_available: ready,
      database_available: databaseAvailable,
      schema_version: schemaVersion,
      ai_enabled: aiEnabled,
      apple_sign_in_configured: appleConfigurationReady(env),
      rewarded_ads_configured: Boolean(String(env.ADMOB_REWARDED_AD_UNIT_ID || "").trim()),
      app_store_verification_configured: Boolean(String(env.APPLE_ROOT_CA_BASE64_JSON || "").trim()),
      message: ready
        ? "GPT-5.6 Lunaを利用できます。"
        : providerProbe.status === "invalid_api_key"
          ? "OpenAI APIキーを確認できませんでした。手動記録は利用できます。"
          : providerProbe.status === "insufficient_permission"
            ? "OpenAI APIキーのモデル参照権限が必要です。手動記録は利用できます。"
            : providerProbe.status === "model_unavailable"
              ? "設定されたOpenAIモデルを利用できません。手動記録は利用できます。"
              : "クラウドAIの設定を準備中です。手動記録は利用できます。",
    }),
    {
      status: ready ? 200 : 503,
      headers: cloudHeaders(),
    },
  );
}

function appleConfigurationReady(env) {
  return [
    "APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_P8",
    "APPLE_REFRESH_TOKEN_ENCRYPTION_KEY",
  ].every((key) => Boolean(String(env[key] || "").trim()));
}

function publicErrorMessage(error) {
  if (error?.status === 401) return String(error.message || "認証情報を確認できませんでした。");
  if ([402, 403, 409].includes(error?.status)) return String(error.message || "この操作を完了できませんでした。");
  if (error?.status === 413) return "送信データが大きすぎます。";
  if (error?.status === 429) return String(error.message || "操作が集中しています。少し待ってから再試行してください。");
  if (error?.status === 422) return "送信内容を確認してください。";
  return "クラウドサービスを利用できません。時間をおいて再試行してください。";
}

function cloudHeaders() {
  return {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "x-bodymode-backend": "cloudflare",
  };
}

function jsonError(status, detail, extraHeaders = {}) {
  return new Response(JSON.stringify({ detail }), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "x-bodymode-backend": "cloudflare",
      ...extraHeaders,
    },
  });
}

function distributionChannel(request) {
  const raw = request.headers.get("x-bodymode-distribution-channel")
    || request.headers.get("x-app-distribution-channel") || "app_store";
  return new Set(["app_store", "testflight", "simulator"]).has(raw) ? raw : "app_store";
}
