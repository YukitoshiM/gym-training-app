import assert from "node:assert/strict";
import test from "node:test";

import { claimSignupCredits, creditSummary } from "../src/cloud/credits.js";
import { cloudOperationsStatus, percentile } from "../src/cloud/operations.js";
import { localD1Fixture } from "../test_support/local-d1.js";

test("operations status is aggregate-only and restricted to the owner", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const client = { subject: "apple:owner", accountKey: "owner-key", isAppleAccount: true };
  const env = { BODYMODE_DB: fixture.database, BODYMODE_UNLIMITED_ACCOUNT_KEYS: "owner-key" };
  await claimSignupCredits(env, client);
  await fixture.database.prepare(`
    INSERT INTO ai_requests(
      request_id, account_key, feature, provider, model, status,
      input_tokens, output_tokens, duration_ms, created_at, finished_at
    ) VALUES ('request-1', ?, 'chat', 'openai', 'gpt-5.6-luna', 'completed', 10, 5, 120, unixepoch(), unixepoch())
  `).bind(client.accountKey).run();
  const status = await cloudOperationsStatus(env, client);
  assert.equal(status.ai.total, 1);
  assert.equal(status.ai.success_rate, 1);
  assert.equal(status.credits.pending_reservations, 0);
  assert.equal(status.ai.p95_duration_ms, 120);
  assert.equal(status.ai.daily_request_limit, 500);
  assert.equal(status.ai.daily_request_utilization, 0.002);
  assert.equal(status.credits.invariant_anomalies, 0);
  assert.equal(status.status, "ok");
  assert.deepEqual(status.alerts, []);
  assert.equal(JSON.stringify(status).includes("apple:owner"), false);
  await assert.rejects(
    cloudOperationsStatus(env, { ...client, accountKey: "someone-else" }),
    (error) => error.code === "admin_required" && error.status === 403,
  );
});

test("operations status reports actionable production alerts", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const client = { subject: "owner", accountKey: "owner-key", isAppleAccount: false };
  const env = {
    BODYMODE_DB: fixture.database,
    BODYMODE_UNLIMITED_ACCOUNT_KEYS: "owner-key",
    BODYMODE_AI_GLOBAL_DAILY_LIMIT: "10",
  };
  await claimSignupCredits(env, client);
  const now = Math.floor(Date.now() / 1_000);
  for (let index = 0; index < 10; index += 1) {
    await fixture.database.prepare(`
      INSERT INTO ai_requests(
        request_id, account_key, feature, provider, model, status,
        duration_ms, error_code, created_at, finished_at
      ) VALUES (?, ?, 'chat', 'openai', 'gpt-5.6-luna', ?, ?, ?, ?, ?)
    `).bind(
      `request-${index}`,
      client.accountKey,
      index < 8 ? "completed" : "failed",
      index < 8 ? 110_000 : null,
      index < 8 ? null : "provider_failed",
      now,
      now,
    ).run();
  }

  const status = await cloudOperationsStatus(env, client);

  assert.equal(status.status, "critical");
  assert.equal(status.ai.success_rate, 0.8);
  assert.equal(status.ai.p95_duration_ms, 110_000);
  assert.equal(status.ai.daily_request_utilization, 1);
  assert.ok(status.alerts.some((item) => item.code === "ai_error_rate_high"));
  assert.ok(status.alerts.some((item) => item.code === "ai_p95_too_slow"));
  assert.ok(status.alerts.some((item) => item.code === "ai_daily_limit_reached"));
});

test("percentile uses the nearest-rank value", () => {
  assert.equal(percentile([], 0.95), 0);
  assert.equal(percentile([10], 0.95), 10);
  assert.equal(percentile([10, 20, 30, 40], 0.5), 20);
  assert.equal(percentile([10, 20, 30, 40], 0.95), 40);
});

test("owner enrollment subject is unlimited without an Apple account", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const env = {
    BODYMODE_DB: fixture.database,
    BODYMODE_UNLIMITED_SUBJECTS: "owner",
  };
  const client = {
    subject: "owner",
    accountKey: "owner-account-fingerprint",
    isAppleAccount: false,
  };

  const summary = await creditSummary(env, client);

  assert.equal(summary.account_required, false);
  assert.equal(summary.enforced, false);
  assert.equal(summary.unlimited, true);
});
