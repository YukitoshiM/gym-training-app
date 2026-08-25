import assert from "node:assert/strict";
import test from "node:test";

import {
  claimSignupCredits,
  completeCreditReservation,
  creditHistory,
  creditSummary,
  releaseCreditReservation,
  reserveCredits,
} from "../src/cloud/credits.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const CLIENT = {
  subject: "apple:test-subject-hash",
  accountKey: "test-account-key",
  isAppleAccount: true,
};

test("signup credits are idempotent and AI failures return reservations", async (t) => {
  const fixture = await creditFixture();
  t.after(() => fixture.dispose());

  const first = await claimSignupCredits(fixture.env, CLIENT);
  const duplicate = await claimSignupCredits(fixture.env, CLIENT);
  assert.equal(first.granted, true);
  assert.equal(first.granted_amount, 20);
  assert.equal(duplicate.granted, false);
  assert.equal(duplicate.balance.available, 20);

  const reservation = await reserveCredits(
    fixture.env, CLIENT, "body_photo", "00000000-0000-4000-8000-000000000001",
  );
  assert.equal((await creditSummary(fixture.env, CLIENT)).balance.available, 16);
  assert.equal((await creditSummary(fixture.env, CLIENT)).balance.reserved, 4);

  await releaseCreditReservation(fixture.env, reservation, "provider_timeout");
  const released = await creditSummary(fixture.env, CLIENT);
  assert.equal(released.balance.available, 20);
  assert.equal(released.balance.reserved, 0);
  assert.equal(released.balance.buckets.signup, 20);
});

test("successful AI requests consume exactly once and produce history", async (t) => {
  const fixture = await creditFixture();
  t.after(() => fixture.dispose());
  await claimSignupCredits(fixture.env, CLIENT);

  const reservation = await reserveCredits(
    fixture.env, CLIENT, "meal", "00000000-0000-4000-8000-000000000002",
  );
  await completeCreditReservation(fixture.env, reservation, {
    model: "gpt-5.6-luna",
    inputTokens: 200,
    outputTokens: 80,
    durationMS: 1_200,
  });
  const summary = await creditSummary(fixture.env, CLIENT);
  assert.equal(summary.balance.available, 17);
  assert.equal(summary.balance.reserved, 0);
  assert.equal(summary.balance.buckets.signup, 17);

  const history = await creditHistory(fixture.env, CLIENT);
  assert.deepEqual(history.events.slice(0, 3).map((event) => event.event_type), [
    "spend", "reserve", "grant",
  ]);
  await assert.rejects(
    reserveCredits(fixture.env, CLIENT, "meal", "00000000-0000-4000-8000-000000000002"),
    (error) => error.code === "credit_request_conflict" && error.status === 409,
  );
});

test("credit enforcement rejects unsigned accounts and insufficient balances", async (t) => {
  const fixture = await creditFixture();
  t.after(() => fixture.dispose());
  const unsigned = await creditSummary(
    fixture.env,
    { ...CLIENT, subject: "compat-user", isAppleAccount: false },
  );
  assert.equal(unsigned.account_required, true);

  await claimSignupCredits(fixture.env, CLIENT);
  for (let index = 0; index < 4; index += 1) {
    const reservation = await reserveCredits(
      fixture.env, CLIENT, "monthly_report", `00000000-0000-4000-8000-00000000001${index}`,
    );
    await completeCreditReservation(fixture.env, reservation);
  }
  await assert.rejects(
    reserveCredits(
      fixture.env, CLIENT, "chat", "00000000-0000-4000-8000-000000000099",
    ),
    (error) => error.code === "insufficient_ai_credits" && error.status === 402,
  );
});

test("unlimited requests keep credits free while recording success and failure usage", async (t) => {
  const fixture = await creditFixture();
  t.after(() => fixture.dispose());
  const env = {
    ...fixture.env,
    BODYMODE_UNLIMITED_ACCOUNT_KEYS: CLIENT.accountKey,
  };
  const database = fixture.env.BODYMODE_DB;
  const successID = "00000000-0000-4000-8000-000000000301";
  const success = await reserveCredits(env, CLIENT, "chat", successID);

  assert.equal(success.unlimited, true);
  assert.equal(success.cost, 0);
  assert.equal((await creditSummary(env, CLIENT)).balance.available, 0);
  assert.equal(
    (await database.prepare(
      "SELECT status FROM ai_requests WHERE request_id = ?",
    ).bind(successID).first()).status,
    "accepted",
  );

  await completeCreditReservation(env, success, {
    model: "gpt-5.6-luna",
    inputTokens: 1_049,
    outputTokens: 25,
    durationMS: 4_200,
  });
  const completed = await database.prepare(`
    SELECT model, status, input_tokens, output_tokens, duration_ms
    FROM ai_requests WHERE request_id = ?
  `).bind(successID).first();
  assert.deepEqual({ ...completed }, {
    model: "gpt-5.6-luna",
    status: "completed",
    input_tokens: 1_049,
    output_tokens: 25,
    duration_ms: 4_200,
  });
  assert.equal(
    Number((await database.prepare(
      "SELECT COUNT(*) AS count FROM credit_reservations WHERE request_id = ?",
    ).bind(successID).first()).count),
    0,
  );
  await assert.rejects(
    reserveCredits(env, CLIENT, "chat", successID),
    (error) => error.code === "credit_request_conflict" && error.status === 409,
  );

  const failureID = "00000000-0000-4000-8000-000000000302";
  const failure = await reserveCredits(env, CLIENT, "chat", failureID);
  await releaseCreditReservation(env, failure, "provider_timeout");
  assert.deepEqual(
    { ...await database.prepare(`
      SELECT status, error_code FROM ai_requests WHERE request_id = ?
    `).bind(failureID).first() },
    { status: "failed", error_code: "provider_timeout" },
  );
});

async function creditFixture() {
  const fixture = localD1Fixture();
  return { env: { BODYMODE_DB: fixture.database }, dispose: fixture.dispose };
}
