import {
  creditBalance,
  ensureCreditAccount,
  grantRewardedAdCredits,
  rewardedAdRemaining,
} from "./credits.js";

const GOOGLE_KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const DAY_LIMIT = 3;
const DEFAULT_REWARD = 5;
const CHALLENGE_LIFETIME_SECONDS = 15 * 60;
const CALLBACK_WINDOW_MS = 24 * 60 * 60 * 1_000;

let cachedKeys = new Map();
let keysLoadedAt = 0;

export class RewardedAdError extends Error {
  constructor(code, status, message) {
    super(message);
    this.name = "RewardedAdError";
    this.code = code;
    this.status = status;
  }
}

export async function createRewardedAdChallenge(env, client) {
  requireAppleAccount(client);
  requireConfiguration(env);
  await ensureCreditAccount(env, client);
  const remaining = await rewardedAdRemaining(env, client.accountKey, utcDayKey());
  if (remaining <= 0) {
    throw new RewardedAdError(
      "rewarded_ad_daily_limit",
      429,
      "本日の動画広告特典は上限に達しました。",
    );
  }
  const challengeID = crypto.randomUUID().toLowerCase();
  const now = unixTime();
  await env.BODYMODE_DB.prepare(`
    INSERT INTO rewarded_ad_challenges(
      challenge_id, account_key, custom_data, status, created_at, expires_at
    ) VALUES (?, ?, ?, 'pending', ?, ?)
  `).bind(
    challengeID,
    client.accountKey,
    challengeID,
    now,
    now + CHALLENGE_LIFETIME_SECONDS,
  ).run();
  return {
    challenge_id: challengeID,
    custom_data: challengeID,
    expires_in: CHALLENGE_LIFETIME_SECONDS,
    remaining_today: remaining,
  };
}

export async function claimRewardedAd(env, client, request) {
  requireAppleAccount(client);
  const payload = await readJSON(request);
  const challengeID = String(payload.challenge_id || "").trim().toLowerCase();
  if (!/^[0-9a-f-]{36}$/.test(challengeID)) {
    throw new RewardedAdError(
      "rewarded_ad_challenge_invalid",
      422,
      "広告特典を確認できませんでした。",
    );
  }
  await expireChallenge(env, challengeID);
  const challenge = await env.BODYMODE_DB.prepare(`
    SELECT account_key, status, transaction_id, expires_at
    FROM rewarded_ad_challenges WHERE challenge_id = ?
  `).bind(challengeID).first();
  if (!challenge || String(challenge.account_key) !== client.accountKey) {
    throw new RewardedAdError(
      "rewarded_ad_challenge_invalid",
      422,
      "広告特典を確認できませんでした。",
    );
  }
  const granted = challenge.status === "granted";
  const pending = new Set(["pending", "verified"]).has(String(challenge.status));
  return {
    granted,
    granted_amount: granted ? rewardAmount(env) : 0,
    remaining_today: await rewardedAdRemaining(env, client.accountKey, utcDayKey()),
    balance: await creditBalance(env, client.accountKey),
    pending,
  };
}

export async function verifyRewardedAdCallback(request, env) {
  requireConfiguration(env);
  const event = await verifyGoogleCallback(request, env);
  const now = unixTime();
  const challenge = await env.BODYMODE_DB.prepare(`
    SELECT account_key, status, transaction_id, expires_at
    FROM rewarded_ad_challenges WHERE challenge_id = ? AND custom_data = ?
  `).bind(event.challengeID, event.challengeID).first();
  if (!challenge) throw invalidCallback();
  if (Number(challenge.expires_at) < Math.floor(event.timestampMS / 1_000)) {
    await rejectChallenge(env, event.challengeID, "expired");
    throw invalidCallback();
  }
  if (challenge.transaction_id != null) {
    if (String(challenge.transaction_id) !== event.transactionID) throw invalidCallback();
    if (new Set(["granted", "rejected"]).has(String(challenge.status))) {
      return { verified: true, granted: challenge.status === "granted" };
    }
  }

  const transactionOwner = await env.BODYMODE_DB.prepare(`
    SELECT challenge_id FROM rewarded_ad_challenges WHERE transaction_id = ?
  `).bind(event.transactionID).first();
  if (transactionOwner) throw invalidCallback();

  if (challenge.transaction_id == null) {
    await env.BODYMODE_DB.prepare(`
      UPDATE rewarded_ad_challenges
      SET status = 'verified', transaction_id = ?, verified_at = ?
      WHERE challenge_id = ? AND status = 'pending' AND transaction_id IS NULL
    `).bind(event.transactionID, now, event.challengeID).run();
  }

  try {
    const result = await grantRewardedAdCredits(env, {
      accountKey: String(challenge.account_key),
      challengeID: event.challengeID,
      transactionID: event.transactionID,
      amount: rewardAmount(env),
      dayKey: utcDayKey(event.timestampMS),
      occurredAt: now,
    });
    await env.BODYMODE_DB.prepare(`
      UPDATE rewarded_ad_challenges SET status = 'granted', granted_at = ?
      WHERE challenge_id = ? AND status IN ('verified', 'granted')
    `).bind(now, event.challengeID).run();
    return { verified: true, granted: result.granted };
  } catch (error) {
    if (String(error?.message || "").includes("rewarded_ad_daily_limit")) {
      await rejectChallenge(env, event.challengeID, "rejected");
      return { verified: true, granted: false };
    }
    throw error;
  }
}

async function verifyGoogleCallback(request, env) {
  const rawQuery = rawQueryString(request.url);
  const parts = rawQuery ? rawQuery.split("&") : [];
  if (parts.length < 2 || !parts.at(-2).startsWith("signature=") || !parts.at(-1).startsWith("key_id=")) {
    throw invalidCallback();
  }
  const signedData = parts.slice(0, -2).join("&");
  const parameters = new URLSearchParams(rawQuery);
  const challengeID = String(parameters.get("custom_data") || "").trim().toLowerCase();
  const transactionID = String(parameters.get("transaction_id") || "").trim();
  const adUnitID = String(parameters.get("ad_unit") || "").trim();
  const reward = Number.parseInt(parameters.get("reward_amount") || "", 10);
  const timestampMS = Number.parseInt(parameters.get("timestamp") || "", 10);
  const keyID = String(parameters.get("key_id") || "").trim();
  if (
    !/^[0-9a-f-]{36}$/.test(challengeID) || !transactionID || !keyID ||
    adUnitID !== String(env.ADMOB_REWARDED_AD_UNIT_ID || "").trim() ||
    !Number.isInteger(reward) || reward <= 0 ||
    !Number.isFinite(timestampMS) || Math.abs(Date.now() - timestampMS) > CALLBACK_WINDOW_MS
  ) throw invalidCallback();

  const pem = await googlePublicKey(keyID, env);
  const publicKey = await crypto.subtle.importKey(
    "spki",
    pemToBytes(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const signature = derECDSAToRaw(base64URLDecode(parameters.get("signature") || ""), 32);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    signature,
    new TextEncoder().encode(signedData),
  );
  if (!valid) throw invalidCallback();
  return { challengeID, transactionID, timestampMS };
}

async function googlePublicKey(keyID, env) {
  if (env.ADMOB_SSV_TEST_PUBLIC_KEYS_JSON && env.BODYMODE_ENV === "test") {
    try {
      const configured = JSON.parse(String(env.ADMOB_SSV_TEST_PUBLIC_KEYS_JSON));
      const pem = configured[String(keyID)];
      if (pem) return String(pem);
    } catch {
      throw invalidCallback();
    }
    throw invalidCallback();
  }
  const cacheSeconds = boundedInteger(env.ADMOB_SSV_KEY_CACHE_SECONDS, 86_400, 300, 604_800);
  if (!cachedKeys.size || Date.now() - keysLoadedAt > cacheSeconds * 1_000 || !cachedKeys.has(keyID)) {
    const response = await fetch(GOOGLE_KEYS_URL, {
      headers: { accept: "application/json" },
      cf: { cacheEverything: true, cacheTtl: cacheSeconds },
    });
    if (!response.ok) {
      throw new RewardedAdError(
        "rewarded_ad_verification_unavailable",
        503,
        "動画広告特典を確認できません。時間をおいて再試行してください。",
      );
    }
    const payload = await response.json();
    const next = new Map();
    for (const item of payload.keys || []) {
      if (item.keyId != null && item.pem) next.set(String(item.keyId), String(item.pem));
    }
    if (!next.size) throw invalidCallback();
    cachedKeys = next;
    keysLoadedAt = Date.now();
  }
  const pem = cachedKeys.get(keyID);
  if (!pem) throw invalidCallback();
  return pem;
}

async function expireChallenge(env, challengeID) {
  await env.BODYMODE_DB.prepare(`
    UPDATE rewarded_ad_challenges SET status = 'expired'
    WHERE challenge_id = ? AND status = 'pending' AND expires_at < ?
  `).bind(challengeID, unixTime()).run();
}

async function rejectChallenge(env, challengeID, status) {
  await env.BODYMODE_DB.prepare(`
    UPDATE rewarded_ad_challenges SET status = ?
    WHERE challenge_id = ? AND status IN ('pending', 'verified')
  `).bind(status, challengeID).run();
}

function requireAppleAccount(client) {
  if (!client?.isAppleAccount) {
    throw new RewardedAdError("account_sign_in_required", 403, "Appleでの登録が必要です。");
  }
}

function requireConfiguration(env) {
  if (!env.BODYMODE_DB || !String(env.ADMOB_REWARDED_AD_UNIT_ID || "").trim()) {
    throw new RewardedAdError(
      "rewarded_ad_verification_unavailable",
      503,
      "動画広告特典を準備中です。時間をおいて再試行してください。",
    );
  }
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    throw new RewardedAdError("invalid_request", 422, "送信内容を確認してください。");
  }
}

function invalidCallback() {
  return new RewardedAdError("invalid_rewarded_ad_callback", 400, "Invalid rewarded ad callback");
}

function rawQueryString(url) {
  const index = String(url).indexOf("?");
  return index < 0 ? "" : String(url).slice(index + 1).split("#", 1)[0];
}

function pemToBytes(pem) {
  const base64 = String(pem).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function base64URLDecode(value) {
  const normalized = String(value).replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
  } catch {
    throw invalidCallback();
  }
}

function derECDSAToRaw(signature, coordinateLength) {
  if (signature.length < 8 || signature[0] !== 0x30) throw invalidCallback();
  let offset = 1;
  const sequence = readDERLength(signature, offset);
  offset = sequence.offset;
  if (offset + sequence.length !== signature.length || signature[offset++] !== 0x02) throw invalidCallback();
  const rLength = readDERLength(signature, offset);
  offset = rLength.offset;
  const r = signature.slice(offset, offset + rLength.length);
  offset += rLength.length;
  if (signature[offset++] !== 0x02) throw invalidCallback();
  const sLength = readDERLength(signature, offset);
  offset = sLength.offset;
  const s = signature.slice(offset, offset + sLength.length);
  if (offset + sLength.length !== signature.length) throw invalidCallback();
  const raw = new Uint8Array(coordinateLength * 2);
  copyCoordinate(r, raw, 0, coordinateLength);
  copyCoordinate(s, raw, coordinateLength, coordinateLength);
  return raw;
}

function readDERLength(bytes, offset) {
  const first = bytes[offset++];
  if (first == null) throw invalidCallback();
  if ((first & 0x80) === 0) return { length: first, offset };
  const count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count > bytes.length) throw invalidCallback();
  let length = 0;
  for (let index = 0; index < count; index += 1) length = (length << 8) | bytes[offset++];
  return { length, offset };
}

function copyCoordinate(source, target, targetOffset, length) {
  let value = source;
  while (value.length > 1 && value[0] === 0) value = value.slice(1);
  if (value.length > length) throw invalidCallback();
  target.set(value, targetOffset + length - value.length);
}

function rewardAmount(env) {
  return boundedInteger(env.AI_REWARDED_AD_CREDITS, DEFAULT_REWARD, 1, 100);
}

function utcDayKey(timestampMS = Date.now()) {
  return new Date(timestampMS).toISOString().slice(0, 10);
}

function unixTime() {
  return Math.floor(Date.now() / 1_000);
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(parsed, maximum));
}

export const rewardedAdConstants = Object.freeze({ dayLimit: DAY_LIMIT, defaultReward: DEFAULT_REWARD });
