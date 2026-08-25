import assert from "node:assert/strict";
import test from "node:test";

import {
  claimRewardedAd,
  createRewardedAdChallenge,
  verifyRewardedAdCallback,
} from "../src/cloud/rewarded-ads.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const CLIENT = {
  subject: "apple:rewarded-test",
  accountKey: "rewarded-account",
  isAppleAccount: true,
};

test("verified rewarded callback grants once and is claimable", async (t) => {
  const fixture = await rewardedFixture();
  t.after(fixture.dispose);
  const challenge = await createRewardedAdChallenge(fixture.env, CLIENT);
  const callback = await signedCallback(fixture, challenge.custom_data, "transaction-1");

  assert.deepEqual(await verifyRewardedAdCallback(callback, fixture.env), {
    verified: true,
    granted: true,
  });
  assert.deepEqual(await verifyRewardedAdCallback(callback, fixture.env), {
    verified: true,
    granted: true,
  });

  const claim = await claimRewardedAd(
    fixture.env,
    CLIENT,
    jsonRequest({ challenge_id: challenge.challenge_id }),
  );
  assert.equal(claim.granted, true);
  assert.equal(claim.granted_amount, 5);
  assert.equal(claim.remaining_today, 2);
  assert.equal(claim.balance.available, 5);
});

test("reward grants are bounded to three per UTC day", async (t) => {
  const fixture = await rewardedFixture();
  t.after(fixture.dispose);
  for (let index = 0; index < 3; index += 1) {
    const challenge = await createRewardedAdChallenge(fixture.env, CLIENT);
    const callback = await signedCallback(fixture, challenge.custom_data, `transaction-${index}`);
    const result = await verifyRewardedAdCallback(callback, fixture.env);
    assert.equal(result.granted, true);
  }
  await assert.rejects(
    createRewardedAdChallenge(fixture.env, CLIENT),
    (error) => error.code === "rewarded_ad_daily_limit" && error.status === 429,
  );
});

test("tampering and cross-account claims are rejected", async (t) => {
  const fixture = await rewardedFixture();
  t.after(fixture.dispose);
  const challenge = await createRewardedAdChallenge(fixture.env, CLIENT);
  const callback = await signedCallback(fixture, challenge.custom_data, "transaction-tamper");
  const tampered = new Request(callback.url.replace("reward_amount=1", "reward_amount=99"));
  await assert.rejects(
    verifyRewardedAdCallback(tampered, fixture.env),
    (error) => error.code === "invalid_rewarded_ad_callback" && error.status === 400,
  );
  await assert.rejects(
    claimRewardedAd(
      fixture.env,
      { ...CLIENT, accountKey: "another-account" },
      jsonRequest({ challenge_id: challenge.challenge_id }),
    ),
    (error) => error.code === "rewarded_ad_challenge_invalid",
  );
});

async function rewardedFixture() {
  const fixture = localD1Fixture();
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const publicDER = new Uint8Array(await crypto.subtle.exportKey("spki", keys.publicKey));
  const pem = `-----BEGIN PUBLIC KEY-----\n${Buffer.from(publicDER).toString("base64")}\n-----END PUBLIC KEY-----`;
  return {
    env: {
      BODYMODE_DB: fixture.database,
      ADMOB_REWARDED_AD_UNIT_ID: "ca-app-pub-test/rewarded",
      ADMOB_SSV_TEST_PUBLIC_KEYS_JSON: JSON.stringify({ 1234567: pem }),
      BODYMODE_ENV: "test",
    },
    privateKey: keys.privateKey,
    dispose: fixture.dispose,
  };
}

async function signedCallback(fixture, challengeID, transactionID) {
  const timestamp = Date.now();
  const signed = [
    "ad_network=5450213213286189855",
    "ad_unit=ca-app-pub-test%2Frewarded",
    `custom_data=${encodeURIComponent(challengeID)}`,
    "reward_amount=1",
    "reward_item=credit",
    `timestamp=${timestamp}`,
    `transaction_id=${encodeURIComponent(transactionID)}`,
  ].join("&");
  const rawSignature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    fixture.privateKey,
    new TextEncoder().encode(signed),
  ));
  const signature = encodeURIComponent(base64URL(rawECDSAToDER(rawSignature)));
  return new Request(`https://example.com/v1/credits/rewarded-ad/ssv?${signed}&signature=${signature}&key_id=1234567`);
}

function rawECDSAToDER(signature) {
  const coordinateLength = signature.length / 2;
  const r = derInteger(signature.slice(0, coordinateLength));
  const s = derInteger(signature.slice(coordinateLength));
  const body = Uint8Array.from([0x02, r.length, ...r, 0x02, s.length, ...s]);
  return Uint8Array.from([0x30, body.length, ...body]);
}

function derInteger(bytes) {
  let value = bytes;
  while (value.length > 1 && value[0] === 0) value = value.slice(1);
  return value[0] & 0x80 ? Uint8Array.from([0, ...value]) : value;
}

function base64URL(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

function jsonRequest(payload) {
  return new Request("https://example.com", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
}
