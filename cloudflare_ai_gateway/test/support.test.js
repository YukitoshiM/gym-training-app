import assert from "node:assert/strict";
import test from "node:test";

import { claimSignupCredits, creditHistory, creditSummary } from "../src/cloud/credits.js";
import { grantSupportCredits } from "../src/cloud/support.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const TARGET = {
  subject: "apple:target",
  accountKey: "1234567890abcdef",
  isAppleAccount: true,
};
const OWNER = { subject: "owner", accountKey: "owner-key", isAppleAccount: false };
const ADJUSTMENT_ID = "01234567-89ab-4def-8123-456789abcdef";

test("owner support grant is audited and idempotent", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const env = {
    BODYMODE_DB: fixture.database,
    BODYMODE_UNLIMITED_ACCOUNT_KEYS: OWNER.accountKey,
  };
  await claimSignupCredits(env, TARGET);
  const request = adjustmentRequest();

  const first = await grantSupportCredits(request, env, OWNER);
  const duplicate = await grantSupportCredits(adjustmentRequest(), env, OWNER);
  const summary = await creditSummary(env, TARGET);
  const history = await creditHistory(env, TARGET);

  assert.equal(first.granted, true);
  assert.equal(first.granted_amount, 25);
  assert.equal(duplicate.granted, false);
  assert.equal(summary.support_id, TARGET.accountKey);
  assert.equal(summary.balance.available, 45);
  assert.equal(history.support_id, TARGET.accountKey);
  assert.equal(history.events[0].source, "admin");
  assert.equal(history.events[0].feature, "purchase_missing");
});

test("support grant rejects non-owner and invalid input", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const env = {
    BODYMODE_DB: fixture.database,
    BODYMODE_UNLIMITED_ACCOUNT_KEYS: OWNER.accountKey,
  };
  await claimSignupCredits(env, TARGET);

  await assert.rejects(
    grantSupportCredits(adjustmentRequest(), env, TARGET),
    (error) => error.code === "admin_required" && error.status === 403,
  );
  await assert.rejects(
    grantSupportCredits(adjustmentRequest({ amount: 501 }), env, OWNER),
    (error) => error.code === "invalid_adjustment_amount" && error.status === 422,
  );
  await assert.rejects(
    grantSupportCredits(adjustmentRequest({ support_id: "ffffffffffffffff" }), env, OWNER),
    (error) => error.code === "support_account_not_found" && error.status === 404,
  );
});

function adjustmentRequest(overrides = {}) {
  return new Request("https://bodymode.example/v1/operations/credits/grant", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      support_id: TARGET.accountKey,
      adjustment_id: ADJUSTMENT_ID,
      amount: 25,
      reason: "purchase_missing",
      ...overrides,
    }),
  });
}
