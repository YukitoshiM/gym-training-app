import assert from "node:assert/strict";
import test from "node:test";

import { appAccountToken } from "../src/cloud/apple.js";
import { cloudFingerprint } from "../src/cloud/auth.js";
import { claimSignupCredits, creditSummary, ensureCreditAccount } from "../src/cloud/credits.js";
import { receiveAppStoreNotification, verifyCreditPurchase } from "../src/cloud/purchases.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const PRODUCT_ID = "com.yukitoshim.gymtrainingapp.credits50";

test("verified StoreKit purchases grant once and refund notifications are idempotent", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const environment = {
    BODYMODE_DB: fixture.database,
    BODYMODE_TOKEN_SIGNING_SECRET: "purchase-test-secret",
    APPLE_CLIENT_ID: "com.yukitoshim.gymtrainingapp",
  };
  const subject = "apple:purchase-test-user";
  const client = {
    subject,
    accountKey: await cloudFingerprint(environment, `credit:${subject}`),
    isAppleAccount: true,
  };
  await ensureCreditAccount(environment, client);
  await claimSignupCredits(environment, client);
  const expectedAccountToken = await appAccountToken(environment, subject);
  const transaction = {
    transactionId: "200000000000001",
    productId: PRODUCT_ID,
    appAccountToken: expectedAccountToken,
    environment: "Sandbox",
  };
  const verifier = {
    async verifyAndDecodeTransaction() { return transaction; },
    async verifyAndDecodeNotification() {
      return {
        notificationUUID: "refund-notification-1",
        notificationType: "REFUND",
        data: { signedTransactionInfo: "t".repeat(130) },
      };
    },
  };

  const first = await verifyCreditPurchase(purchaseRequest(), environment, client, { verifier });
  const duplicate = await verifyCreditPurchase(purchaseRequest(), environment, client, { verifier });
  assert.equal(first.granted, true);
  assert.equal(first.granted_amount, 50);
  assert.equal(duplicate.granted, false);
  assert.equal((await creditSummary(environment, client)).balance.available, 70);

  const notification = notificationRequest();
  assert.deepEqual(await receiveAppStoreNotification(notification, environment, { verifier }), { accepted: true });
  assert.deepEqual(await receiveAppStoreNotification(notificationRequest(), environment, { verifier }), { accepted: true });
  assert.equal((await creditSummary(environment, client)).balance.available, 20);
});

test("purchase verification rejects another account token", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const environment = {
    BODYMODE_DB: fixture.database,
    BODYMODE_TOKEN_SIGNING_SECRET: "purchase-test-secret",
    APPLE_CLIENT_ID: "com.yukitoshim.gymtrainingapp",
  };
  const subject = "apple:purchase-test-user";
  const client = {
    subject,
    accountKey: await cloudFingerprint(environment, `credit:${subject}`),
    isAppleAccount: true,
  };
  const verifier = {
    async verifyAndDecodeTransaction() {
      return {
        transactionId: "200000000000002",
        productId: PRODUCT_ID,
        appAccountToken: "00000000-0000-4000-8000-000000000099",
      };
    },
  };
  await assert.rejects(
    verifyCreditPurchase(purchaseRequest(), environment, client, { verifier }),
    (error) => error.code === "purchase_account_mismatch" && error.status === 403,
  );
});

function purchaseRequest() {
  return new Request("https://bodymode.example/v1/credits/purchases/verify", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ signed_transaction: "s".repeat(130) }),
  });
}

function notificationRequest() {
  return new Request("https://bodymode.example/v1/app-store/notifications", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ signedPayload: "n".repeat(130) }),
  });
}
