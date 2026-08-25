import assert from "node:assert/strict";
import test from "node:test";

import gateway from "../src/index.js";


test("rejects routes outside the explicit API allowlist", async () => {
  const response = await gateway.fetch(
    new Request("https://bodymode.example/internal/health"),
    configuredEnvironment(),
  );

  assert.equal(response.status, 404);
  assert.equal((await response.json()).detail.code, "route_not_found");
});

test("rejects unsupported methods", async () => {
  const response = await gateway.fetch(
    new Request("https://bodymode.example/v1/agents/chat", { method: "GET" }),
    configuredEnvironment(),
  );

  assert.equal(response.status, 405);
  assert.equal(response.headers.get("allow"), "POST");
});

test("does not expose an invalid origin configuration", async () => {
  const response = await gateway.fetch(
    new Request("https://bodymode.example/v1/health"),
    { BODYMODE_ORIGIN_URL: "http://private-host.local", BODYMODE_GATEWAY_KEY: "secret" },
  );

  const body = await response.text();
  assert.equal(response.status, 503);
  assert.equal(JSON.parse(body).detail.code, "gateway_not_configured");
  assert.equal(body.includes("private-host"), false);
});

test("rejects oversized requests before contacting the origin", async () => {
  const response = await gateway.fetch(
    new Request("https://bodymode.example/v1/meals/analyze-image", {
      method: "POST",
      headers: { "content-length": String(13 * 1024 * 1024) },
      body: "{}",
    }),
    configuredEnvironment(),
  );

  assert.equal(response.status, 413);
  assert.equal((await response.json()).detail.code, "request_too_large");
});

test("forwards only approved headers and hides origin response metadata", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    assert.equal(String(target), "https://origin.example/v1/usage");
    assert.equal(init.headers.get("authorization"), "Bearer access-token");
    assert.equal(init.headers.get("x-bodymode-gateway-key"), "test-gateway-key");
    assert.equal(init.headers.get("x-private-client-value"), null);
    return new Response('{"features":[]}', {
      status: 200,
      headers: {
        "content-type": "application/json",
        "server": "private-origin",
        "x-request-id": "request-123",
      },
    });
  };

  try {
    const response = await gateway.fetch(
      new Request("https://bodymode.example/v1/usage", {
        headers: {
          authorization: "Bearer access-token",
          "x-private-client-value": "do-not-forward",
        },
      }),
      configuredEnvironment(),
    );

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("server"), null);
    assert.equal(response.headers.get("x-request-id"), "request-123");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("forwards App Store signed notifications without app authorization", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    assert.equal(String(target), "https://origin.example/v1/app-store/notifications");
    assert.equal(init.method, "POST");
    assert.equal(init.headers.get("authorization"), null);
    assert.equal(init.headers.get("x-bodymode-gateway-key"), "test-gateway-key");
    assert.deepEqual(JSON.parse(await new Response(init.body).text()), {
      signedPayload: "apple-signed-payload",
    });
    return new Response(null, { status: 204 });
  };

  try {
    const response = await gateway.fetch(
      new Request("https://bodymode.example/v1/app-store/notifications", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ signedPayload: "apple-signed-payload" }),
      }),
      configuredEnvironment(),
    );

    assert.equal(response.status, 204);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("accepts only the fixed AdMob callback verification probe", async () => {
  const verificationURL = new URL("https://bodymode.example/v1/credits/rewarded-ad/ssv");
  verificationURL.search = new URLSearchParams({
    ad_network: "5450213213286189855",
    ad_unit: "1234567890",
    reward_amount: "5",
    reward_item: "AI Credits",
    timestamp: "1700000000000",
    transaction_id: "123456789",
    signature: "verification-signature",
    key_id: "3335741209",
  });

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => {
    assert.fail("The AdMob verification probe must not reach the reward origin");
  };

  try {
    const response = await gateway.fetch(
      new Request(verificationURL, {
        headers: { "user-agent": "Google-AdMob-Reward-Verification" },
      }),
      configuredEnvironment(),
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { verified: true });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("does not accept a spoofed AdMob verification probe", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(null, { status: 400 });

  try {
    const response = await gateway.fetch(
      new Request(
        "https://bodymode.example/v1/credits/rewarded-ad/ssv?ad_network=5450213213286189855&ad_unit=1234567890&transaction_id=123456789&timestamp=1&signature=x&key_id=1",
      ),
      configuredEnvironment(),
    );

    assert.equal(response.status, 400);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("keeps all routes on the origin when cloud migration is not enabled", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (target) => {
    assert.equal(String(target), "https://origin.example/v1/health");
    return new Response('{"status":"ok","runtime":"mac-mini"}', {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  try {
    const response = await gateway.fetch(
      new Request("https://bodymode.example/v1/health"),
      configuredEnvironment(),
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).runtime, "mac-mini");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("moves only explicitly selected routes to the Cloudflare runtime", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    assert.equal(String(target), "https://api.openai.com/v1/models/gpt-5.6-luna");
    assert.equal(init.method, "GET");
    assert.equal(init.headers.authorization, "Bearer secret-key");
    return Response.json({ id: "gpt-5.6-luna", object: "model", owned_by: "openai" });
  };

  try {
    const response = await gateway.fetch(
      new Request("https://bodymode.example/v1/health"),
      {
        BODYMODE_CLOUD_ROUTES: "/v1/health",
        BODYMODE_OPENAI_MODEL: "gpt-5.6-luna",
        OPENAI_API_KEY: "secret-key",
        BODYMODE_DB: {
          prepare: () => ({ first: async () => ({ value: "5" }) }),
        },
      },
    );
    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-bodymode-backend"), "cloudflare");
    assert.equal(payload.runtime, "cloudflare");
    assert.equal(payload.model_available, true);
    assert.equal(payload.provider_authenticated, true);
    assert.equal(payload.provider_probe_status, "ok");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("reports a degraded cloud health state when the provider secret is absent", async () => {
  const response = await gateway.fetch(
    new Request("https://bodymode.example/v1/health"),
    { BODYMODE_CLOUD_ROUTES: "/v1/health" },
  );
  assert.equal(response.status, 503);
  assert.equal((await response.json()).status, "degraded");
});

test("reports degraded health when OpenAI rejects the configured key", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json(
    { error: { code: "invalid_api_key" } },
    { status: 401 },
  );

  try {
    const response = await gateway.fetch(
      new Request("https://bodymode.example/v1/health"),
      {
        BODYMODE_CLOUD_ROUTES: "/v1/health",
        BODYMODE_OPENAI_MODEL: "gpt-5.6-luna",
        OPENAI_API_KEY: "invalid-key",
        BODYMODE_DB: {
          prepare: () => ({ first: async () => ({ value: "5" }) }),
        },
      },
    );
    const payload = await response.json();
    assert.equal(response.status, 503);
    assert.equal(payload.model_available, false);
    assert.equal(payload.provider_reachable, true);
    assert.equal(payload.provider_authenticated, false);
    assert.equal(payload.provider_probe_status, "invalid_api_key");
    assert.equal(JSON.stringify(payload).includes("invalid-key"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

function configuredEnvironment() {
  return {
    BODYMODE_ORIGIN_URL: "https://origin.example",
    BODYMODE_GATEWAY_KEY: "test-gateway-key",
  };
}
