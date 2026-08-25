import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";

import { appleClientSecret, createAppleAccount, verifyAppleIdentityToken } from "../src/cloud/apple.js";
import { authenticateCloudRequest } from "../src/cloud/auth.js";
import { createEnrollmentSession } from "../src/cloud/sessions.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const TOKEN_SECRET = "cloud-token-secret-for-tests";
const CLIENT_ID = "com.yukitoshim.gymtrainingapp";

test("issues an enrollment token from a hashed key and verifies it at the edge", async () => {
  const enrollmentKey = "test-enrollment-key";
  const environment = {
    BODYMODE_TOKEN_SIGNING_SECRET: TOKEN_SECRET,
    BODYMODE_ENROLLMENT_KEY_HASHES: JSON.stringify({
      "beta:test": `sha256:${createHash("sha256").update(enrollmentKey).digest("hex")}`,
    }),
  };
  const response = await createEnrollmentSession(new Request("https://example.com/v1/auth/token", {
    method: "POST",
    headers: { authorization: `Bearer ${enrollmentKey}`, "content-type": "application/json" },
    body: JSON.stringify({ installation_id: "00000000-0000-4000-8000-000000000001", app_version: "1.0" }),
  }), environment);
  assert.equal(response.token_type, "Bearer");
  const client = await authenticateCloudRequest(new Request("https://example.com/v1/coaches", {
    headers: { authorization: `Bearer ${response.access_token}` },
  }), environment);
  assert.equal(client.subject, "beta:test");
  assert.equal(client.isAppleAccount, false);
});

test("verifies Apple signature, audience, expiry, and hashed nonce", async () => {
  const identity = identityFixture();
  const rawNonce = "valid-raw-nonce-value";
  const token = identity.token({ nonce: createHash("sha256").update(rawNonce).digest("hex") });
  const claims = await verifyAppleIdentityToken(token, rawNonce, { APPLE_CLIENT_ID: CLIENT_ID }, {
    fetchImpl: identity.keysFetch,
  });
  assert.equal(claims.sub, "apple-user-1");
  await assert.rejects(
    verifyAppleIdentityToken(token, "wrong-raw-nonce-value", { APPLE_CLIENT_ID: CLIENT_ID }, {
      fetchImpl: identity.keysFetch,
    }),
    (error) => error.code === "invalid_apple_nonce",
  );
});

test("creates one Apple account grant and encrypts the refresh token", async (t) => {
  const fixture = localD1Fixture();
  t.after(fixture.dispose);
  const identity = identityFixture();
  const clientPrivateKey = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey;
  const rawNonce = "valid-raw-nonce-value";
  const identityToken = identity.token({ nonce: createHash("sha256").update(rawNonce).digest("hex") });
  const exchangedToken = identity.token({ nonce: undefined });
  const environment = {
    BODYMODE_DB: fixture.database,
    BODYMODE_TOKEN_SIGNING_SECRET: TOKEN_SECRET,
    APPLE_CLIENT_ID: CLIENT_ID,
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_PRIVATE_KEY_P8: clientPrivateKey.export({ type: "pkcs8", format: "pem" }),
    APPLE_REFRESH_TOKEN_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString("base64"),
  };
  const fetchImpl = async (url, init = {}) => {
    if (url === "https://appleid.apple.com/auth/keys") return identity.keysFetch(url, init);
    if (url === "https://appleid.apple.com/auth/token") {
      const body = new URLSearchParams(init.body);
      assert.equal(body.get("client_id"), CLIENT_ID);
      assert.equal(body.get("grant_type"), "authorization_code");
      assert.equal(body.get("client_secret").split(".").length, 3);
      return Response.json({ refresh_token: "sensitive-refresh-token", id_token: exchangedToken });
    }
    throw new Error(`unexpected URL ${url}`);
  };
  const requestBody = {
    identity_token: identityToken,
    authorization_code: "single-use-code",
    raw_nonce: rawNonce,
    installation_id: "00000000-0000-4000-8000-000000000001",
    app_version: "1.0",
  };
  const first = await createAppleAccount(jsonRequest(requestBody), environment, { fetchImpl });
  const second = await createAppleAccount(jsonRequest(requestBody), environment, { fetchImpl });
  assert.equal(first.signup_granted, true);
  assert.equal(first.signup_granted_amount, 20);
  assert.equal(second.signup_granted, false);
  assert.equal(second.credits.available, 20);

  const stored = await fixture.database.prepare(
    "SELECT encrypted_token FROM apple_refresh_tokens LIMIT 1",
  ).first();
  assert.ok(stored.encrypted_token);
  assert.equal(stored.encrypted_token.includes("sensitive-refresh-token"), false);
});

test("creates a valid ES256 Apple client secret", async () => {
  const privateKey = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey;
  const token = await appleClientSecret({
    APPLE_CLIENT_ID: CLIENT_ID,
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_PRIVATE_KEY_P8: privateKey.export({ type: "pkcs8", format: "pem" }),
  });
  const [header, claims, signature] = token.split(".");
  assert.equal(JSON.parse(Buffer.from(header, "base64url")).alg, "ES256");
  assert.equal(JSON.parse(Buffer.from(claims, "base64url")).sub, CLIENT_ID);
  assert.equal(Buffer.from(signature, "base64url").length, 64);
});

function identityFixture() {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const publicJWK = publicKey.export({ format: "jwk" });
  const kid = "apple-test-key";
  const keysFetch = async () => Response.json({ keys: [{ ...publicJWK, kid, alg: "RS256", use: "sig" }] });
  return {
    keysFetch,
    token(overrides = {}) {
      const now = Math.floor(Date.now() / 1_000);
      const header = Buffer.from(JSON.stringify({ alg: "RS256", kid })).toString("base64url");
      const claims = Buffer.from(JSON.stringify({
        iss: "https://appleid.apple.com", aud: CLIENT_ID, sub: "apple-user-1",
        iat: now - 5, exp: now + 300, ...overrides,
      })).toString("base64url");
      const signature = createHashAndSign(`${header}.${claims}`, privateKey);
      return `${header}.${claims}.${signature}`;
    },
  };
}

function createHashAndSign(value, privateKey) {
  return sign("RSA-SHA256", Buffer.from(value), privateKey).toString("base64url");
}

function jsonRequest(body) {
  return new Request("https://example.com/v1/account/apple", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
}
