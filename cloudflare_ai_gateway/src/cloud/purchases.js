import { appAccountToken } from "./apple.js";
import {
  creditSummary,
  ensureCreditAccount,
  grantPurchaseCredits,
  refundPurchaseCredits,
} from "./credits.js";

const PRODUCTS = Object.freeze({
  "com.yukitoshim.gymtrainingapp.credits50": 50,
  "com.yukitoshim.gymtrainingapp.credits150": 150,
  "com.yukitoshim.gymtrainingapp.credits500": 500,
});

export class CloudPurchaseVerificationError extends Error {
  constructor(code = "invalid_app_store_transaction", status = 422, message = "購入情報を確認できませんでした。") {
    super(message);
    this.name = "CloudPurchaseVerificationError";
    this.code = code;
    this.status = status;
  }
}

export async function verifyCreditPurchase(request, env, client, options = {}) {
  if (!client.isAppleAccount) throw new CloudPurchaseVerificationError("account_required", 403, "購入にはAppleアカウント登録が必要です。");
  const body = await readJSON(request);
  const signedTransaction = String(body?.signed_transaction || "");
  if (signedTransaction.length < 128 || signedTransaction.length > 100_000) {
    throw new CloudPurchaseVerificationError();
  }
  const transaction = await verifyTransaction(signedTransaction, env, options);
  const credits = PRODUCTS[String(transaction.productId || "")];
  if (!credits || !transaction.transactionId) throw new CloudPurchaseVerificationError();
  if (transaction.revocationDate || transaction.revocationReason != null) {
    throw new CloudPurchaseVerificationError("refunded_app_store_transaction", 422, "返金済みの購入は利用できません。");
  }
  const expectedToken = await appAccountToken(env, client.subject);
  if (!transaction.appAccountToken || String(transaction.appAccountToken).toLowerCase() !== expectedToken) {
    throw new CloudPurchaseVerificationError("purchase_account_mismatch", 403, "購入情報が別のアカウントに紐づいています。");
  }
  await ensureCreditAccount(env, client);
  const granted = await grantPurchaseCredits(env, {
    accountKey: client.accountKey,
    amount: credits,
    transactionKey: `app_store:${transaction.transactionId}`,
  });
  return {
    granted: granted.granted,
    granted_amount: granted.granted ? granted.grantedAmount : 0,
    transaction_id: String(transaction.transactionId),
    product_id: String(transaction.productId),
    balance: (await creditSummary(env, client)).balance,
  };
}

export async function receiveAppStoreNotification(request, env, options = {}) {
  const body = await readJSON(request);
  const signedPayload = String(body?.signedPayload || "");
  if (signedPayload.length < 128 || signedPayload.length > 200_000) {
    throw new CloudPurchaseVerificationError("invalid_app_store_notification", 400, "App Store通知を確認できませんでした。");
  }
  const notification = await verifyNotification(signedPayload, env, options);
  const eventKey = String(notification.notificationUUID || "");
  const notificationType = String(notification.notificationType || "");
  if (!eventKey) throw new CloudPurchaseVerificationError("invalid_app_store_notification", 400);
  const existing = await env.BODYMODE_DB.prepare(
    "SELECT status FROM webhook_events WHERE event_key = ?",
  ).bind(eventKey).first();
  if (existing?.status === "processed") return { accepted: true };
  await env.BODYMODE_DB.prepare(`
    INSERT OR IGNORE INTO webhook_events(event_key, event_type, received_at, status)
    VALUES (?, ?, unixepoch(), 'received')
  `).bind(eventKey, notificationType).run();

  if (["REFUND", "REVOKE"].includes(notificationType)) {
    const signedTransaction = notification?.data?.signedTransactionInfo;
    if (!signedTransaction) throw new CloudPurchaseVerificationError("missing_refund_transaction", 400);
    const transaction = await verifyTransaction(signedTransaction, env, options);
    const credits = PRODUCTS[String(transaction.productId || "")];
    if (credits && transaction.transactionId) {
      await refundPurchaseCredits(env, {
        transactionKey: `app_store:${transaction.transactionId}`,
        amount: credits,
      });
    }
  }
  await env.BODYMODE_DB.prepare(`
    UPDATE webhook_events SET status = 'processed', processed_at = unixepoch()
    WHERE event_key = ?
  `).bind(eventKey).run();
  return { accepted: true };
}

async function verifyTransaction(signedData, env, options) {
  try {
    const verifier = await verifierForSignedData(signedData, env, options);
    return await verifier.verifyAndDecodeTransaction(signedData);
  } catch {
    throw new CloudPurchaseVerificationError();
  }
}

async function verifyNotification(signedData, env, options) {
  try {
    const verifier = await verifierForSignedData(signedData, env, options);
    return await verifier.verifyAndDecodeNotification(signedData);
  } catch {
    throw new CloudPurchaseVerificationError("invalid_app_store_notification", 400, "App Store通知を確認できませんでした。");
  }
}

async function verifierForSignedData(signedData, env, options = {}) {
  if (options.verifier) return options.verifier;
  const { Environment, SignedDataVerifier } = await import("@apple/app-store-server-library");
  const unverified = decodeJWSPayload(signedData);
  const environment = unverified.environment === "Sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
  const roots = appleRoots(env).map((value) => Buffer.from(value, "base64"));
  return new SignedDataVerifier(
    roots,
    String(env.APPLE_ENABLE_ONLINE_CHECKS || "true").toLowerCase() !== "false",
    environment,
    String(env.APPLE_CLIENT_ID || "com.yukitoshim.gymtrainingapp"),
    environment === Environment.PRODUCTION ? Number(env.APPLE_APP_ID || 0) : undefined,
  );
}

function appleRoots(env) {
  try {
    const roots = JSON.parse(String(env.APPLE_ROOT_CA_BASE64_JSON || "[]"));
    if (!Array.isArray(roots) || !roots.length || roots.some((root) => !String(root))) throw new Error();
    return roots;
  } catch {
    throw new CloudPurchaseVerificationError("apple_roots_not_configured", 503, "購入検証を準備中です。");
  }
}

function decodeJWSPayload(value) {
  try {
    const payload = String(value).split(".")[1];
    return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  } catch {
    throw new CloudPurchaseVerificationError();
  }
}

async function readJSON(request) {
  try { return await request.json(); }
  catch { throw new CloudPurchaseVerificationError("invalid_json", 422, "送信内容を確認してください。"); }
}
