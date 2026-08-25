import { handleCloudRoute } from "./cloud/router.js";
import { runCloudMaintenance } from "./cloud/maintenance.js";

const ALLOWED_ROUTES = new Map([
  ["/v1/auth/token", new Set(["POST"])],
  ["/v1/auth/revoke", new Set(["POST"])],
  ["/v1/account/apple", new Set(["POST"])],
  ["/v1/account", new Set(["DELETE"])],
  ["/v1/health", new Set(["GET"])],
  ["/v1/coaches", new Set(["GET"])],
  ["/v1/evidence/status", new Set(["GET"])],
  ["/v1/usage", new Set(["GET"])],
  ["/v1/credits", new Set(["GET"])],
  ["/v1/credits/history", new Set(["GET"])],
  ["/v1/credits/signup-grant", new Set(["POST"])],
  ["/v1/credits/rewarded-ad/claim", new Set(["POST"])],
  ["/v1/credits/rewarded-ad/challenge", new Set(["POST"])],
  ["/v1/credits/rewarded-ad/ssv", new Set(["GET"])],
  ["/v1/credits/purchases/verify", new Set(["POST"])],
  ["/v1/app-store/notifications", new Set(["POST"])],
  ["/v1/operations/status", new Set(["GET"])],
  ["/v1/operations/credits/grant", new Set(["POST"])],
  ["/v1/analytics/events", new Set(["POST", "DELETE"])],
  ["/v1/agents/chat", new Set(["POST"])],
  ["/v1/meals/analyze-image", new Set(["POST"])],
  ["/v1/meals/analyze-text", new Set(["POST"])],
  ["/v1/body-photos/analyze", new Set(["POST"])],
  ["/v1/body-photos/analyze-set", new Set(["POST"])],
  ["/v1/reports/weekly", new Set(["POST"])],
  ["/v1/reports/monthly", new Set(["POST"])],
]);

const FORWARDED_REQUEST_HEADERS = [
  "accept",
  "authorization",
  "content-type",
  "x-request-id",
  "x-bodymode-distribution-channel",
  "x-app-distribution-channel",
];

const FORWARDED_RESPONSE_HEADERS = [
  "content-type",
  "retry-after",
  "x-request-id",
];

export default {
  async fetch(request, env) {
    const incomingURL = new URL(request.url);
    const methods = ALLOWED_ROUTES.get(incomingURL.pathname);
    if (!methods) {
      return jsonError(404, "route_not_found", "このAPIは利用できません。");
    }
    if (!methods.has(request.method)) {
      return jsonError(405, "method_not_allowed", "この操作は利用できません。", {
        Allow: [...methods].join(", "),
      });
    }

    if (isAdMobVerificationProbe(request, incomingURL)) {
      return new Response(JSON.stringify({ verified: true }), {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
          "x-content-type-options": "nosniff",
        },
      });
    }

    const cloudResponse = await handleCloudRoute(request, env, incomingURL);
    if (cloudResponse) return cloudResponse;

    const contentLength = Number(request.headers.get("content-length") || "0");
    if (contentLength > 12 * 1024 * 1024) {
      return jsonError(413, "request_too_large", "送信データが大きすぎます。");
    }

    if (!env.BODYMODE_ORIGIN_URL || !env.BODYMODE_GATEWAY_KEY) {
      return jsonError(503, "gateway_not_configured", "AIゲートウェイを準備中です。");
    }

    let origin;
    try {
      origin = new URL(env.BODYMODE_ORIGIN_URL);
    } catch {
      console.error(JSON.stringify({
        event: "origin_unreachable",
        route: incomingURL.pathname,
        method: request.method,
        request_id: String(request.headers.get("x-request-id") || "").slice(0, 80),
      }));
      return jsonError(503, "gateway_not_configured", "AIゲートウェイを準備中です。");
    }
    if (origin.protocol !== "https:") {
      return jsonError(503, "gateway_not_configured", "AIゲートウェイを準備中です。");
    }

    const target = new URL(incomingURL.pathname + incomingURL.search, origin);
    const headers = new Headers();
    for (const name of FORWARDED_REQUEST_HEADERS) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    headers.set("x-bodymode-gateway-key", env.BODYMODE_GATEWAY_KEY);
    headers.set("x-forwarded-proto", "https");

    try {
      const upstream = await fetch(target, {
        method: request.method,
        headers,
        body: ["GET", "DELETE"].includes(request.method) ? undefined : request.body,
        redirect: "manual",
      });
      const responseHeaders = new Headers({
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      });
      for (const name of FORWARDED_RESPONSE_HEADERS) {
        const value = upstream.headers.get(name);
        if (value) responseHeaders.set(name, value);
      }
      return new Response(upstream.body, {
        status: upstream.status,
        headers: responseHeaders,
      });
    } catch {
      return jsonError(
        502,
        "origin_unreachable",
        "AIサーバーに接続できません。時間をおいて再試行してください。",
        { "Retry-After": "30" },
      );
    }
  },
  async scheduled(_event, env, context) {
    context.waitUntil(runCloudMaintenance(env));
  },
};

function isAdMobVerificationProbe(request, url) {
  if (
    url.pathname !== "/v1/credits/rewarded-ad/ssv" ||
    request.headers.get("user-agent") !== "Google-AdMob-Reward-Verification"
  ) {
    return false;
  }

  const parameters = url.searchParams;
  return (
    parameters.get("ad_network") === "5450213213286189855" &&
    parameters.get("ad_unit") === "1234567890" &&
    parameters.get("transaction_id") === "123456789" &&
    parameters.has("timestamp") &&
    parameters.has("signature") &&
    parameters.has("key_id") &&
    !parameters.has("custom_data")
  );
}

function jsonError(status, code, message, extraHeaders = {}) {
  return new Response(JSON.stringify({ detail: { code, message } }), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}
