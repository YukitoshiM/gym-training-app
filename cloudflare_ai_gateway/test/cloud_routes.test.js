import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import gateway from "../src/index.js";

const TOKEN_SECRET = "test-token-signing-secret";

test("serves coaches at the edge only for a valid existing access token", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => assert.fail("migrated route reached origin");
  try {
    const response = await gateway.fetch(
      authorizedRequest("https://bodymode.example/v1/coaches"),
      cloudEnvironment(),
    );
    const coaches = await response.json();
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-bodymode-backend"), "cloudflare");
    assert.deepEqual(coaches.map((coach) => coach.id), [
      "fat_loss", "hypertrophy", "strength", "body_recomposition", "wellness", "return_to_training",
    ]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("rejects invalid access tokens without contacting the origin", async () => {
  const response = await gateway.fetch(
    new Request("https://bodymode.example/v1/coaches", {
      headers: { authorization: "Bearer invalid.token" },
    }),
    cloudEnvironment(),
  );
  assert.equal(response.status, 401);
  assert.equal((await response.json()).detail.code, "invalid_access_token");
});

test("reports the migrated D1 evidence inventory", async () => {
  const environment = cloudEnvironment();
  environment.BODYMODE_DB.evidence = {
    documents: 2_844,
    usable_documents: 2_844,
    vector_chunks: 2_844,
    last_updated_at: 1_787_350_000,
  };
  const response = await gateway.fetch(
    authorizedRequest("https://bodymode.example/v1/evidence/status"),
    environment,
  );
  const status = await response.json();
  assert.equal(response.status, 200);
  assert.equal(status.state, "ready");
  assert.equal(status.documents, 2_844);
  assert.equal(status.runtime, "cloudflare");
});

test("stores allowlisted anonymous analytics and deletes only that installation", async () => {
  const environment = cloudEnvironment();
  const event = {
    id: "00000000-0000-4000-8000-000000000001",
    occurred_at: Math.floor(Date.now() / 1_000),
    name: "daily_action_completed",
    dimension: "home",
    properties: {
      goal: "muscleGain",
      actionCategory: "workout",
      position: 0,
      completionMethod: "automatic",
    },
    app_version: "1.0 (28)",
    locale: "en-US",
    channel: "testflight",
  };
  const stored = await gateway.fetch(
    authorizedRequest("https://bodymode.example/v1/analytics/events", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ events: [event] }),
    }),
    environment,
  );
  assert.equal(stored.status, 200);
  assert.deepEqual(await stored.json(), { accepted: 1 });
  assert.equal(environment.BODYMODE_DB.events.size, 1);
  const saved = [...environment.BODYMODE_DB.events.values()][0];
  assert.equal(saved[2], "daily_action_completed");
  assert.equal(JSON.parse(saved[4]).goal, "muscleGain");

  const deleted = await gateway.fetch(
    authorizedRequest("https://bodymode.example/v1/analytics/events", { method: "DELETE" }),
    environment,
  );
  assert.equal(deleted.status, 200);
  assert.deepEqual(await deleted.json(), { deleted: 1 });
  assert.equal(environment.BODYMODE_DB.events.size, 0);
});

test("rejects analytics fields outside the privacy allowlist", async () => {
  const response = await gateway.fetch(
    authorizedRequest("https://bodymode.example/v1/analytics/events", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        events: [{
          id: "00000000-0000-4000-8000-000000000002",
          occurred_at: Math.floor(Date.now() / 1_000),
          name: "app_opened",
          properties: { weight: "80kg" },
          app_version: "1.0",
          locale: "ja-JP",
          channel: "testflight",
        }],
      }),
    }),
    cloudEnvironment(),
  );
  assert.equal(response.status, 422);
  assert.equal((await response.json()).detail.code, "invalid_analytics_event");
});

function authorizedRequest(url, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set("authorization", `Bearer ${accessToken()}`);
  return new Request(url, { ...init, headers });
}

function accessToken() {
  const payload = Buffer.from(JSON.stringify({
    sub: "apple:test-user",
    device: "hashed-device",
    jti: "test-token-id",
    iat: Math.floor(Date.now() / 1_000),
    exp: Math.floor(Date.now() / 1_000) + 3_600,
  })).toString("base64url");
  const signature = createHmac("sha256", TOKEN_SECRET).update(payload).digest("base64url");
  return `${payload}.${signature}`;
}

function cloudEnvironment() {
  return {
    BODYMODE_CLOUD_ROUTES: "/v1/coaches,/v1/evidence/status,/v1/analytics/events",
    BODYMODE_TOKEN_SIGNING_SECRET: TOKEN_SECRET,
    BODYMODE_DB: new FakeD1(),
  };
}

class FakeD1 {
  constructor() {
    this.events = new Map();
    this.revoked = new Set();
    this.evidence = { documents: 0, usable_documents: 0, vector_chunks: 0, last_updated_at: null };
  }

  prepare(sql) {
    return new FakeStatement(this, sql);
  }

  async batch(statements) {
    const results = [];
    for (const statement of statements) results.push(await statement.run());
    return results;
  }
}

class FakeStatement {
  constructor(database, sql, values = []) {
    this.database = database;
    this.sql = sql.replace(/\s+/g, " ").trim();
    this.values = values;
  }

  bind(...values) {
    return new FakeStatement(this.database, this.sql, values);
  }

  async first() {
    if (this.sql.includes("FROM revoked_access_tokens")) {
      return this.database.revoked.has(this.values[0]) ? { token_id: this.values[0] } : null;
    }
    if (this.sql.includes("FROM evidence_documents")) return this.database.evidence;
    return null;
  }

  async run() {
    if (this.sql.startsWith("DELETE FROM anonymous_events WHERE expires_at")) {
      return { meta: { changes: 0 } };
    }
    if (this.sql.startsWith("INSERT OR IGNORE INTO anonymous_events")) {
      const id = this.values[0];
      if (this.database.events.has(id)) return { meta: { changes: 0 } };
      this.database.events.set(id, this.values);
      return { meta: { changes: 1 } };
    }
    if (this.sql.startsWith("DELETE FROM anonymous_events WHERE installation_key")) {
      let changes = 0;
      for (const [id, values] of this.database.events) {
        if (values[1] !== this.values[0]) continue;
        this.database.events.delete(id);
        changes += 1;
      }
      return { meta: { changes } };
    }
    return { meta: { changes: 0 } };
  }
}
