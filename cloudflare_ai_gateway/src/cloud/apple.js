import { cloudFingerprint, issueCloudAccessToken } from "./auth.js";
import { claimSignupCredits, ensureCreditAccount, featureCosts } from "./credits.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export class CloudAppleIdentityError extends Error {
  constructor(code, status = 401, message = "Appleアカウントを確認できませんでした。もう一度お試しください。") {
    super(message);
    this.name = "CloudAppleIdentityError";
    this.code = code;
    this.status = status;
  }
}

export async function createAppleAccount(request, env, options = {}) {
  requireAppleConfiguration(env);
  const payload = await readJSON(request);
  validateAccountRequest(payload);
  const identity = await verifyAppleIdentityToken(payload.identity_token, payload.raw_nonce, env, options);
  const exchanged = await exchangeAppleAuthorizationCode(payload.authorization_code, env, options);
  const exchangedIdentity = await verifyAppleIdentityToken(exchanged.id_token, null, env, options);
  if (identity.sub !== exchangedIdentity.sub) {
    throw new CloudAppleIdentityError("apple_subject_mismatch", 401);
  }

  const stableHash = await cloudFingerprint(env, `apple-subject:${identity.sub}`, 64);
  const subject = `apple:${stableHash}`;
  const token = await issueCloudAccessToken(
    env,
    subject,
    payload.installation_id,
    boundedInteger(env.AI_APPLE_ACCOUNT_TOKEN_TTL_SECONDS, 2_592_000, 300, 2_592_000),
  );
  const accountKey = await cloudFingerprint(env, `credit:${subject}`);
  const client = { subject, accountKey, isAppleAccount: true };
  await ensureCreditAccount(env, client);
  await env.BODYMODE_DB.prepare(
    "UPDATE accounts SET deleted_at = NULL WHERE account_key = ?",
  ).bind(accountKey).run();
  await storeRefreshToken(env, accountKey, exchanged.refresh_token);
  const signup = await claimSignupCredits(env, client);
  return {
    ...token,
    signup_granted: signup.granted,
    signup_granted_amount: signup.granted_amount,
    credits: signup.balance,
    feature_costs: featureCosts(env),
    app_account_token: await appAccountToken(env, subject),
  };
}

export async function deleteAppleAccount(env, client, options = {}) {
  if (!client.isAppleAccount) {
    throw new CloudAppleIdentityError("account_required", 403, "削除できるアカウントがありません。");
  }
  requireAppleConfiguration(env);
  const rows = await env.BODYMODE_DB.prepare(`
    SELECT token_id, encrypted_token, initialization_vector
    FROM apple_refresh_tokens WHERE account_key = ? ORDER BY created_at
  `).bind(client.accountKey).all();
  for (const row of rows?.results || []) {
    const refreshToken = await decryptRefreshToken(
      env, client.accountKey, row.encrypted_token, row.initialization_vector,
    );
    await revokeAppleToken(refreshToken, env, options);
  }
  const balance = await env.BODYMODE_DB.prepare(
    "SELECT available, reserved FROM credit_accounts WHERE account_key = ?",
  ).bind(client.accountKey).first();
  const removedCredits = Number(balance?.available || 0) + Number(balance?.reserved || 0);
  const now = unixTime();
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare("DELETE FROM apple_refresh_tokens WHERE account_key = ?").bind(client.accountKey),
    env.BODYMODE_DB.prepare("DELETE FROM credit_reservation_allocations WHERE request_id IN (SELECT request_id FROM credit_reservations WHERE account_key = ?)").bind(client.accountKey),
    env.BODYMODE_DB.prepare("DELETE FROM ai_requests WHERE account_key = ?").bind(client.accountKey),
    env.BODYMODE_DB.prepare("DELETE FROM credit_events WHERE account_key = ?").bind(client.accountKey),
    env.BODYMODE_DB.prepare("DELETE FROM credit_reservations WHERE account_key = ?").bind(client.accountKey),
    env.BODYMODE_DB.prepare("DELETE FROM credit_lots WHERE account_key = ?").bind(client.accountKey),
    env.BODYMODE_DB.prepare("DELETE FROM credit_accounts WHERE account_key = ?").bind(client.accountKey),
    env.BODYMODE_DB.prepare("UPDATE accounts SET deleted_at = ? WHERE account_key = ?").bind(now, client.accountKey),
  ]);
  return { removed_credits: removedCredits };
}

export async function verifyAppleIdentityToken(token, rawNonce, env, options = {}) {
  const segments = String(token || "").split(".");
  if (segments.length !== 3) throw new CloudAppleIdentityError("invalid_apple_identity");
  const header = decodeJWTPart(segments[0]);
  const claims = decodeJWTPart(segments[1]);
  if (header.alg !== "RS256" || !header.kid) throw new CloudAppleIdentityError("invalid_apple_identity");
  const fetchImpl = options.fetchImpl || fetch;
  const keysResponse = await fetchImpl(APPLE_KEYS_URL, { headers: { accept: "application/json" } });
  if (!keysResponse.ok) throw new CloudAppleIdentityError("apple_keys_unavailable", 503, "Apple認証を利用できません。時間をおいて再試行してください。");
  const keySet = await keysResponse.json();
  const jwk = (keySet?.keys || []).find((key) => key.kid === header.kid && key.alg === "RS256");
  if (!jwk) throw new CloudAppleIdentityError("invalid_apple_identity");
  const verificationKey = await crypto.subtle.importKey(
    "jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"],
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    verificationKey,
    decodeBase64URL(segments[2]),
    new TextEncoder().encode(`${segments[0]}.${segments[1]}`),
  );
  const clientID = String(env.APPLE_CLIENT_ID || "");
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  const now = unixTime();
  if (
    !valid || claims.iss !== APPLE_ISSUER || !audiences.includes(clientID) ||
    !claims.sub || Number(claims.exp || 0) <= now || Number(claims.iat || 0) > now + 300
  ) throw new CloudAppleIdentityError("invalid_apple_identity");
  if (rawNonce != null) {
    const expectedNonce = await sha256Hex(String(rawNonce));
    if (!claims.nonce || claims.nonce !== expectedNonce) {
      throw new CloudAppleIdentityError("invalid_apple_nonce");
    }
  }
  return claims;
}

export async function exchangeAppleAuthorizationCode(code, env, options = {}) {
  const response = await (options.fetchImpl || fetch)(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: new URLSearchParams({
      client_id: String(env.APPLE_CLIENT_ID),
      client_secret: await appleClientSecret(env),
      code: String(code),
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) throw new CloudAppleIdentityError("apple_token_exchange_failed", 503, "Appleアカウント連携を完了できませんでした。時間をおいて再試行してください。");
  const result = await response.json();
  if (!result?.refresh_token || !result?.id_token) {
    throw new CloudAppleIdentityError("apple_token_exchange_failed", 503, "Appleアカウント連携を完了できませんでした。時間をおいて再試行してください。");
  }
  return result;
}

export async function revokeAppleToken(token, env, options = {}) {
  const response = await (options.fetchImpl || fetch)(APPLE_REVOKE_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: new URLSearchParams({
      client_id: String(env.APPLE_CLIENT_ID),
      client_secret: await appleClientSecret(env),
      token: String(token),
      token_type_hint: "refresh_token",
    }),
  });
  if (!response.ok) throw new CloudAppleIdentityError("apple_revocation_failed", 503, "Appleとの連携解除を完了できませんでした。時間をおいて再試行してください。");
}

export async function appleClientSecret(env) {
  const now = unixTime();
  const header = encodeJWTPart({ alg: "ES256", kid: String(env.APPLE_KEY_ID), typ: "JWT" });
  const claims = encodeJWTPart({
    iss: String(env.APPLE_TEAM_ID), iat: now, exp: now + 300,
    aud: APPLE_ISSUER, sub: String(env.APPLE_CLIENT_ID),
  });
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(String(env.APPLE_PRIVATE_KEY_P8)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${encodeBase64URL(new Uint8Array(signature))}`;
}

async function storeRefreshToken(env, accountKey, refreshToken) {
  const tokenID = await cloudFingerprint(env, `apple-refresh:${refreshToken}`, 64);
  const existing = await env.BODYMODE_DB.prepare(
    "SELECT token_id FROM apple_refresh_tokens WHERE token_id = ?",
  ).bind(tokenID).first();
  if (existing) return;
  const key = await refreshEncryptionKey(env, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(accountKey) },
    key,
    new TextEncoder().encode(refreshToken),
  );
  await env.BODYMODE_DB.prepare(`
    INSERT INTO apple_refresh_tokens(
      token_id, account_key, encrypted_token, initialization_vector, created_at
    ) VALUES (?, ?, ?, ?, ?)
  `).bind(
    tokenID, accountKey, encodeBase64URL(new Uint8Array(encrypted)),
    encodeBase64URL(iv), unixTime(),
  ).run();
}

async function decryptRefreshToken(env, accountKey, encrypted, initializationVector) {
  const key = await refreshEncryptionKey(env, ["decrypt"]);
  const decrypted = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: decodeBase64URL(initializationVector),
      additionalData: new TextEncoder().encode(accountKey),
    },
    key,
    decodeBase64URL(encrypted),
  );
  return new TextDecoder().decode(decrypted);
}

async function refreshEncryptionKey(env, usages) {
  const bytes = decodeBase64URL(String(env.APPLE_REFRESH_TOKEN_ENCRYPTION_KEY || ""));
  if (bytes.length !== 32) throw new CloudAppleIdentityError("apple_encryption_not_configured", 503, "Appleアカウント連携を準備中です。");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, usages);
}

export async function appAccountToken(env, subject) {
  const bytes = hexToBytes(await cloudFingerprint(env, `purchase:${subject}`, 32));
  const uuid = new Uint8Array(bytes.slice(0, 16));
  uuid[6] = (uuid[6] & 0x0f) | 0x40;
  uuid[8] = (uuid[8] & 0x3f) | 0x80;
  const hex = [...uuid].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function requireAppleConfiguration(env) {
  for (const key of ["APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_P8", "APPLE_REFRESH_TOKEN_ENCRYPTION_KEY"]) {
    if (!String(env[key] || "").trim()) throw new CloudAppleIdentityError("apple_sign_in_unavailable", 503, "Appleでサインインを準備中です。時間をおいて再試行してください。");
  }
  if (!env.BODYMODE_DB) throw new CloudAppleIdentityError("cloud_database_not_configured", 503);
}

function validateAccountRequest(payload) {
  if (
    String(payload?.identity_token || "").length < 64 || String(payload?.identity_token || "").length > 16_384 ||
    String(payload?.authorization_code || "").length < 8 || String(payload?.authorization_code || "").length > 8_192 ||
    String(payload?.raw_nonce || "").length < 16 || String(payload?.raw_nonce || "").length > 256 ||
    String(payload?.installation_id || "").length < 16 || String(payload?.installation_id || "").length > 128
  ) throw new CloudAppleIdentityError("invalid_apple_request", 422, "Apple認証の入力を確認してください。");
}

async function readJSON(request) {
  try { return await request.json(); } catch { throw new CloudAppleIdentityError("invalid_json", 422, "送信内容を確認してください。"); }
}

function decodeJWTPart(value) {
  try { return JSON.parse(new TextDecoder().decode(decodeBase64URL(value))); }
  catch { throw new CloudAppleIdentityError("invalid_apple_identity"); }
}

function encodeJWTPart(value) {
  return encodeBase64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToBytes(value) {
  const body = value.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  if (!body) throw new CloudAppleIdentityError("apple_private_key_invalid", 503);
  return decodeBase64URL(body);
}

function encodeBase64URL(value) {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decodeBase64URL(value) {
  const base64 = String(value || "").replaceAll("-", "+").replaceAll("_", "/")
    + "=".repeat((4 - (String(value || "").length % 4)) % 4);
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function hexToBytes(value) {
  return Uint8Array.from(String(value).match(/.{1,2}/g) || [], (part) => Number.parseInt(part, 16));
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? Math.max(minimum, Math.min(parsed, maximum)) : fallback;
}

function unixTime() { return Math.floor(Date.now() / 1_000); }
