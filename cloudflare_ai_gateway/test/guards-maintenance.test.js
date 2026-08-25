import assert from "node:assert/strict";
import test from "node:test";

import { claimSignupCredits, creditSummary, reserveCredits } from "../src/cloud/credits.js";
import { enforceAIGenerationGuards, enforceAuthenticatedLimit } from "../src/cloud/guards.js";
import { runCloudMaintenance } from "../src/cloud/maintenance.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const CLIENT = {
  subject: "apple:guard-test",
  accountKey: "guard-account",
  isAppleAccount: true,
};

test("AI kill switch and per-account rate limit fail before provider use", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  await assert.rejects(
    enforceAIGenerationGuards({ BODYMODE_DB: fixture.database, BODYMODE_AI_ENABLED: "0" }, CLIENT),
    (error) => error.code === "ai_temporarily_disabled" && error.status === 503,
  );
  const env = { BODYMODE_DB: fixture.database };
  await enforceAuthenticatedLimit(env, CLIENT, "test", { limit: 1, windowSeconds: 60 });
  await assert.rejects(
    enforceAuthenticatedLimit(env, CLIENT, "test", { limit: 1, windowSeconds: 60 }),
    (error) => error.code === "rate_limit_exceeded" && error.status === 429,
  );
});

test("maintenance returns stale credit reservations", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const env = { BODYMODE_DB: fixture.database, AI_CREDIT_SIGNUP_BONUS: "20" };
  await claimSignupCredits(env, CLIENT);
  const requestID = "00000000-0000-4000-8000-000000000201";
  await reserveCredits(env, CLIENT, "body_photo", requestID);
  await fixture.database.prepare(
    "UPDATE credit_reservations SET created_at = unixepoch() - 10000 WHERE request_id = ?",
  ).bind(requestID).run();
  assert.equal((await creditSummary(env, CLIENT)).balance.reserved, 4);
  const result = await runCloudMaintenance(env);
  assert.equal(result.released_reservations, 1);
  const summary = await creditSummary(env, CLIENT);
  assert.equal(summary.balance.available, 20);
  assert.equal(summary.balance.reserved, 0);
});
