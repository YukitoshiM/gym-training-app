import { creditBalance, grantCredits, isUnlimitedClient } from "./credits.js";

const ADJUSTMENT_REASONS = new Set([
  "purchase_missing",
  "reward_missing",
  "service_recovery",
  "other",
]);

export async function grantSupportCredits(request, env, client) {
  requireOwner(env, client);
  const payload = await readJSON(request);
  const supportID = String(payload.support_id || "").trim().toLowerCase();
  const adjustmentID = String(payload.adjustment_id || "").trim().toLowerCase();
  const reason = String(payload.reason || "").trim();
  const amount = Number(payload.amount);

  if (!/^[a-f0-9]{16}$/.test(supportID)) {
    throw supportError("invalid_support_id", 422, "サポートIDを確認してください。");
  }
  if (!isUUID(adjustmentID)) {
    throw supportError("invalid_adjustment_id", 422, "補正IDを確認してください。");
  }
  if (!Number.isInteger(amount) || amount < 1 || amount > 500) {
    throw supportError("invalid_adjustment_amount", 422, "付与量は1から500で指定してください。");
  }
  if (!ADJUSTMENT_REASONS.has(reason)) {
    throw supportError("invalid_adjustment_reason", 422, "補正理由を確認してください。");
  }

  const account = await env.BODYMODE_DB.prepare(`
    SELECT account_key FROM accounts
    WHERE account_key = ? AND deleted_at IS NULL
  `).bind(supportID).first();
  if (!account) {
    throw supportError("support_account_not_found", 404, "対象アカウントが見つかりません。");
  }

  const transactionKey = `admin:${adjustmentID}`;
  const granted = await grantCredits(env, {
    accountKey: supportID,
    source: "admin",
    amount,
    transactionKey,
    feature: reason,
  });
  return {
    support_id: supportID,
    adjustment_id: adjustmentID,
    reason,
    granted,
    granted_amount: granted ? amount : 0,
    balance: await creditBalance(env, supportID),
  };
}

function requireOwner(env, client) {
  if (isUnlimitedClient(env, client)) return;
  throw supportError("admin_required", 403, "管理者だけが実行できます。");
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    throw supportError("invalid_request_body", 422, "入力内容を確認してください。");
  }
}

function isUUID(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
}

function supportError(code, status, message) {
  const error = new Error(message);
  error.code = code;
  error.status = status;
  return error;
}
