export class CloudAuthenticationError extends Error {
  constructor(code = "invalid_access_token", message = "認証情報を確認できませんでした。") {
    super(message);
    this.name = "CloudAuthenticationError";
    this.code = code;
    this.status = 401;
  }
}

export async function authenticateCloudRequest(request, env) {
  const secret = String(env.BODYMODE_TOKEN_SIGNING_SECRET || "");
  if (!secret) {
    const error = new Error("cloud_token_verification_not_configured");
    error.status = 503;
    error.code = "cloud_auth_not_configured";
    throw error;
  }

  const authorization = request.headers.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) throw new CloudAuthenticationError();
  const token = authorization.slice("Bearer ".length).trim();
  const segments = token.split(".");
  if (segments.length !== 2) throw new CloudAuthenticationError();

  const [encodedPayload, encodedSignature] = segments;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  let signature;
  let payload;
  try {
    signature = decodeBase64URL(encodedSignature);
    const verified = await crypto.subtle.verify(
      "HMAC",
      key,
      signature,
      new TextEncoder().encode(encodedPayload),
    );
    if (!verified) throw new Error("signature");
    payload = JSON.parse(new TextDecoder().decode(decodeBase64URL(encodedPayload)));
  } catch {
    throw new CloudAuthenticationError();
  }

  const subject = String(payload?.sub || "");
  const device = String(payload?.device || "");
  const tokenId = String(payload?.jti || "");
  const expiresAt = Number(payload?.exp || 0);
  if (!subject || !device || !tokenId || !Number.isInteger(expiresAt)) {
    throw new CloudAuthenticationError();
  }
  if (expiresAt <= Math.floor(Date.now() / 1_000)) {
    throw new CloudAuthenticationError("access_token_expired", "認証の有効期限が切れました。");
  }

  if (env.BODYMODE_DB) {
    const revoked = await env.BODYMODE_DB.prepare(
      "SELECT token_id FROM revoked_access_tokens WHERE token_id = ? AND expires_at > unixepoch()",
    ).bind(tokenId).first();
    if (revoked) {
      throw new CloudAuthenticationError("access_token_revoked", "認証情報は失効しています。");
    }
  }
  const client = {
    subject,
    device,
    tokenId,
    expiresAt,
    installationKey: (await keyedFingerprint(key, `${subject}:${device}`)).slice(0, 16),
    accountKey: (await keyedFingerprint(key, `credit:${subject}`)).slice(0, 16),
    isAppleAccount: subject.startsWith("apple:"),
  };
  if (client.isAppleAccount && env.BODYMODE_DB) {
    const account = await env.BODYMODE_DB.prepare(
      "SELECT deleted_at FROM accounts WHERE account_key = ?",
    ).bind(client.accountKey).first();
    if (Number(account?.deleted_at || 0) > 0) {
      throw new CloudAuthenticationError("account_deleted", "アカウントは削除されています。");
    }
  }
  return client;
}

export async function issueCloudAccessToken(env, subject, device, ttlSeconds = 86_400) {
  const secret = String(env.BODYMODE_TOKEN_SIGNING_SECRET || "");
  if (!secret) {
    const error = new Error("cloud_token_signing_not_configured");
    error.status = 503;
    error.code = "cloud_auth_not_configured";
    throw error;
  }
  const now = Math.floor(Date.now() / 1_000);
  const ttl = Math.max(300, Math.min(Number(ttlSeconds || 86_400), 2_592_000));
  const payload = encodeBase64URL(new TextEncoder().encode(JSON.stringify({
    sub: String(subject),
    device: String(device),
    jti: crypto.randomUUID(),
    iat: now,
    exp: now + ttl,
  })));
  const key = await signingKey(secret);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return {
    access_token: `${payload}.${encodeBase64URL(new Uint8Array(signature))}`,
    token_type: "Bearer",
    expires_in: ttl,
  };
}

export async function cloudFingerprint(env, value, length = 16) {
  const secret = String(env.BODYMODE_TOKEN_SIGNING_SECRET || "");
  if (!secret) throw new Error("cloud_token_signing_not_configured");
  return (await keyedFingerprint(await signingKey(secret), value)).slice(0, length);
}

async function keyedFingerprint(key, value) {
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function signingKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function encodeBase64URL(value) {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decodeBase64URL(value) {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/")
    + "=".repeat((4 - (value.length % 4)) % 4);
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
