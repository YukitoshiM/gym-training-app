import { createAppleAccount, deleteAppleAccount } from "./apple.js";
import { issueCloudAccessToken } from "./auth.js";

export async function createEnrollmentSession(request, env) {
  const credential = bearerCredential(request);
  const subject = await enrollmentSubject(env, credential);
  if (!subject) throw sessionError("invalid_enrollment_credential", 401, "認証情報を確認できませんでした。");
  const payload = await readJSON(request);
  const installationID = String(payload?.installation_id || "");
  const appVersion = String(payload?.app_version || "");
  if (installationID.length < 16 || installationID.length > 128 || appVersion.length > 40) {
    throw sessionError("invalid_session_request", 422, "送信内容を確認してください。");
  }
  return issueCloudAccessToken(
    env,
    subject,
    installationID,
    boundedInteger(env.AI_TOKEN_TTL_SECONDS, 86_400, 300, 604_800),
  );
}

export async function createAppleSession(request, env) {
  return createAppleAccount(request, env);
}

export async function revokeCloudSession(env, client) {
  if (client.tokenId === "legacy-shared-key") {
    throw sessionError("legacy_token_not_revocable", 422, "この認証情報は失効できません。");
  }
  await env.BODYMODE_DB.prepare(`
    INSERT OR REPLACE INTO revoked_access_tokens(
      token_id, account_key, expires_at, revoked_at
    ) VALUES (?, ?, ?, unixepoch())
  `).bind(
    client.tokenId,
    client.isAppleAccount ? client.accountKey : null,
    client.expiresAt,
  ).run();
  return null;
}

export async function deleteCloudAccount(env, client) {
  return deleteAppleAccount(env, client);
}

async function enrollmentSubject(env, credential) {
  const digest = await sha256Hex(credential);
  let entries = {};
  try {
    entries = JSON.parse(String(env.BODYMODE_ENROLLMENT_KEY_HASHES || "{}"));
  } catch {
    throw sessionError("enrollment_configuration_invalid", 503, "認証サービスを準備中です。");
  }
  for (const [subject, stored] of Object.entries(entries)) {
    const expected = String(stored || "").replace(/^sha256:/, "").toLowerCase();
    if (expected.length === 64 && timingSafeHexEqual(digest, expected)) return String(subject);
  }
  return null;
}

function bearerCredential(request) {
  const authorization = request.headers.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    throw sessionError("authorization_required", 401, "認証情報が必要です。");
  }
  const credential = authorization.slice("Bearer ".length).trim();
  if (!credential || credential.length > 512) {
    throw sessionError("invalid_enrollment_credential", 401, "認証情報を確認できませんでした。");
  }
  return credential;
}

async function readJSON(request) {
  try { return await request.json(); }
  catch { throw sessionError("invalid_json", 422, "送信内容を確認してください。"); }
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function timingSafeHexEqual(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function sessionError(code, status, message) {
  const error = new Error(message); error.code = code; error.status = status; return error;
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? Math.max(minimum, Math.min(parsed, maximum)) : fallback;
}
