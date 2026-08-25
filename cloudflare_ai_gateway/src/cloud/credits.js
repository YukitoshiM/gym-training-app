const DEFAULT_FEATURE_COSTS = Object.freeze({
  chat: 1,
  daily_recommendation: 1,
  plan_generation: 2,
  meal: 3,
  body_photo: 4,
  weekly_report: 5,
  monthly_report: 5,
});

const CREDIT_SOURCES = new Set(["signup", "rewarded_ad", "purchase", "admin"]);

export class CloudCreditError extends Error {
  constructor(code, status, message, details = {}) {
    super(message);
    this.name = "CloudCreditError";
    this.code = code;
    this.status = status;
    this.details = details;
  }
}

export function featureCosts(env) {
  return Object.fromEntries(Object.entries(DEFAULT_FEATURE_COSTS).map(([feature, fallback]) => [
    feature,
    boundedInteger(env[`AI_CREDIT_COST_${feature.toUpperCase()}`], fallback, 1, 100),
  ]));
}

export async function creditSummary(env, client) {
  requireDatabase(env);
  const unlimited = isUnlimitedClient(env, client);
  if (!client.isAppleAccount && !unlimited) {
    return {
      account_required: true,
      enforced: true,
      unlimited: false,
      balance: null,
      feature_costs: featureCosts(env),
      signup_bonus: signupBonus(env),
    };
  }

  await ensureCreditAccount(env, client);
  return {
    account_required: false,
    enforced: !unlimited,
    unlimited,
    support_id: client.accountKey,
    balance: await readBalance(env, client.accountKey),
    feature_costs: featureCosts(env),
    signup_bonus: signupBonus(env),
  };
}

export async function creditHistory(env, client, limit = 100) {
  requireCreditAccount(client, env);
  await ensureCreditAccount(env, client);
  const boundedLimit = boundedInteger(limit, 100, 1, 200);
  const result = await env.BODYMODE_DB.prepare(`
    SELECT id, event_type, amount, source, feature, occurred_at
    FROM credit_events
    WHERE account_key = ?
    ORDER BY occurred_at DESC, id DESC
    LIMIT ?
  `).bind(client.accountKey, boundedLimit).all();
  return {
    support_id: client.accountKey,
    events: (result?.results || []).map((event) => ({
      id: Number(event.id),
      event_type: String(event.event_type),
      amount: Number(event.amount),
      source: event.source == null ? null : String(event.source),
      feature: event.feature == null ? null : String(event.feature),
      occurred_at: Number(event.occurred_at),
    })),
    balance: await readBalance(env, client.accountKey),
  };
}

export async function creditBalance(env, accountKey) {
  requireDatabase(env);
  return readBalance(env, accountKey);
}

export function isUnlimitedClient(env, client) {
  return unlimitedAccountKeys(env).has(client?.accountKey)
    || unlimitedSubjects(env).has(client?.subject);
}

export async function rewardedAdRemaining(env, accountKey, dayKey) {
  requireDatabase(env);
  const result = await env.BODYMODE_DB.prepare(`
    SELECT COUNT(*) AS count FROM rewarded_ad_grants
    WHERE account_key = ? AND day_key = ?
  `).bind(accountKey, dayKey).first();
  return Math.max(0, 3 - Number(result?.count || 0));
}

export async function grantRewardedAdCredits(
  env,
  { accountKey, challengeID, transactionID, amount, dayKey, occurredAt },
) {
  requireDatabase(env);
  const normalizedAmount = boundedInteger(amount, 0, 0, 100);
  if (!normalizedAmount) throw new TypeError("invalid_reward_amount");
  const transactionKey = `rewarded_ad:${transactionID}`;
  const existing = await env.BODYMODE_DB.prepare(`
    SELECT account_key, challenge_id, granted_amount
    FROM rewarded_ad_grants WHERE transaction_id = ?
  `).bind(transactionID).first();
  if (existing) {
    if (
      String(existing.account_key) !== accountKey ||
      String(existing.challenge_id) !== challengeID ||
      Number(existing.granted_amount) !== normalizedAmount
    ) throw new CloudCreditError("credit_transaction_conflict", 409, "広告報酬の取引が競合しました。");
    return { granted: false, amount: 0 };
  }

  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(`
      INSERT INTO rewarded_ad_grants(
        transaction_id, challenge_id, account_key, day_key, granted_amount, granted_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    `).bind(transactionID, challengeID, accountKey, dayKey, normalizedAmount, occurredAt),
    env.BODYMODE_DB.prepare(`
      INSERT INTO credit_lots(
        account_key, source, original_amount, remaining_amount, transaction_key, created_at
      ) VALUES (?, 'rewarded_ad', ?, ?, ?, ?)
    `).bind(accountKey, normalizedAmount, normalizedAmount, transactionKey, occurredAt),
    env.BODYMODE_DB.prepare(`
      UPDATE credit_accounts SET available = available + ?, updated_at = ?
      WHERE account_key = ?
    `).bind(normalizedAmount, occurredAt, accountKey),
    env.BODYMODE_DB.prepare(`
      INSERT INTO credit_events(
        account_key, event_type, amount, source, transaction_key, occurred_at
      ) VALUES (?, 'grant', ?, 'rewarded_ad', ?, ?)
    `).bind(accountKey, normalizedAmount, transactionKey, occurredAt),
  ]);
  return { granted: true, amount: normalizedAmount };
}

export async function claimSignupCredits(env, client) {
  requireCreditAccount(client, env);
  await ensureCreditAccount(env, client);
  const amount = signupBonus(env);
  if (amount <= 0) {
    return { granted: false, granted_amount: 0, balance: await readBalance(env, client.accountKey) };
  }
  const granted = await grantCredits(env, {
    accountKey: client.accountKey,
    source: "signup",
    amount,
    transactionKey: `signup:${client.accountKey}`,
  });
  return {
    granted,
    granted_amount: granted ? amount : 0,
    balance: await readBalance(env, client.accountKey),
  };
}

export async function grantCredits(env, { accountKey, source, amount, transactionKey, feature = null }) {
  requireDatabase(env);
  if (!CREDIT_SOURCES.has(source)) throw new TypeError("unsupported_credit_source");
  const normalizedAmount = boundedInteger(amount, 0, 0, 1_000_000);
  if (!normalizedAmount) return false;
  const existing = await env.BODYMODE_DB.prepare(
    "SELECT account_key, source, original_amount FROM credit_lots WHERE transaction_key = ?",
  ).bind(transactionKey).first();
  if (existing) {
    if (
      String(existing.account_key) !== accountKey ||
      String(existing.source) !== source ||
      Number(existing.original_amount) !== normalizedAmount
    ) {
      throw new CloudCreditError("credit_transaction_conflict", 409, "クレジット取引が競合しました。");
    }
    return false;
  }

  const now = unixTime();
  try {
    await env.BODYMODE_DB.batch([
      env.BODYMODE_DB.prepare(`
        INSERT INTO credit_lots(
          account_key, source, original_amount, remaining_amount,
          transaction_key, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
      `).bind(accountKey, source, normalizedAmount, normalizedAmount, transactionKey, now),
      env.BODYMODE_DB.prepare(`
        UPDATE credit_accounts
        SET available = available + ?, updated_at = ?
        WHERE account_key = ?
      `).bind(normalizedAmount, now, accountKey),
      env.BODYMODE_DB.prepare(`
        INSERT INTO credit_events(
          account_key, event_type, amount, source, feature, transaction_key, occurred_at
        ) VALUES (?, 'grant', ?, ?, ?, ?, ?)
      `).bind(accountKey, normalizedAmount, source, feature, transactionKey, now),
    ]);
    return true;
  } catch (error) {
    const raced = await env.BODYMODE_DB.prepare(
      "SELECT account_key, source, original_amount FROM credit_lots WHERE transaction_key = ?",
    ).bind(transactionKey).first();
    if (
      raced &&
      String(raced.account_key) === accountKey &&
      String(raced.source) === source &&
      Number(raced.original_amount) === normalizedAmount
    ) return false;
    throw error;
  }
}

export async function grantPurchaseCredits(env, { accountKey, amount, transactionKey }) {
  requireDatabase(env);
  const normalizedAmount = boundedInteger(amount, 0, 0, 1_000_000);
  if (!normalizedAmount) throw new TypeError("invalid_purchase_amount");
  const existing = await env.BODYMODE_DB.prepare(
    "SELECT account_key, original_amount FROM credit_lots WHERE transaction_key = ?",
  ).bind(transactionKey).first();
  if (existing) {
    if (String(existing.account_key) !== accountKey || Number(existing.original_amount) !== normalizedAmount) {
      throw new CloudCreditError("purchase_transaction_conflict", 409, "購入取引が競合しました。");
    }
    return { granted: false, grantedAmount: 0 };
  }
  const refundedBeforeGrant = await env.BODYMODE_DB.prepare(
    "SELECT status FROM purchase_adjustments WHERE transaction_key = ?",
  ).bind(transactionKey).first();
  const now = unixTime();
  if (refundedBeforeGrant) {
    await env.BODYMODE_DB.batch([
      env.BODYMODE_DB.prepare(`
        INSERT INTO credit_lots(
          account_key, source, original_amount, remaining_amount, transaction_key, created_at
        ) VALUES (?, 'purchase', ?, 0, ?, ?)
      `).bind(accountKey, normalizedAmount, transactionKey, now),
      env.BODYMODE_DB.prepare(`
        UPDATE purchase_adjustments SET account_key = ? WHERE transaction_key = ?
      `).bind(accountKey, transactionKey),
    ]);
    return { granted: false, grantedAmount: 0 };
  }

  const debts = await env.BODYMODE_DB.prepare(`
    SELECT transaction_key, remaining_debt
    FROM purchase_adjustments
    WHERE account_key = ? AND remaining_debt > 0
    ORDER BY adjusted_at, transaction_key
  `).bind(accountKey).all();
  let remaining = normalizedAmount;
  const debtStatements = [];
  for (const debt of debts?.results || []) {
    const applied = Math.min(remaining, Number(debt.remaining_debt || 0));
    if (applied <= 0) continue;
    remaining -= applied;
    debtStatements.push(env.BODYMODE_DB.prepare(`
      UPDATE purchase_adjustments
      SET remaining_debt = remaining_debt - ?
      WHERE transaction_key = ? AND remaining_debt >= ?
    `).bind(applied, debt.transaction_key, applied));
    debtStatements.push(env.BODYMODE_DB.prepare(`
      INSERT INTO credit_events(
        account_key, event_type, amount, source, feature, transaction_key, occurred_at
      ) VALUES (?, 'spend', ?, 'purchase', 'refund_adjustment', ?, ?)
    `).bind(accountKey, applied, `${transactionKey}:debt:${debt.transaction_key}`, now));
    if (!remaining) break;
  }
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(`
      INSERT INTO credit_lots(
        account_key, source, original_amount, remaining_amount, transaction_key, created_at
      ) VALUES (?, 'purchase', ?, ?, ?, ?)
    `).bind(accountKey, normalizedAmount, remaining, transactionKey, now),
    env.BODYMODE_DB.prepare(`
      UPDATE credit_accounts SET available = available + ?, updated_at = ? WHERE account_key = ?
    `).bind(remaining, now, accountKey),
    ...debtStatements,
    ...(remaining > 0 ? [env.BODYMODE_DB.prepare(`
      INSERT INTO credit_events(
        account_key, event_type, amount, source, transaction_key, occurred_at
      ) VALUES (?, 'grant', ?, 'purchase', ?, ?)
    `).bind(accountKey, remaining, transactionKey, now)] : []),
  ]);
  return { granted: true, grantedAmount: remaining };
}

export async function refundPurchaseCredits(env, { transactionKey, amount }) {
  requireDatabase(env);
  const normalizedAmount = boundedInteger(amount, 0, 0, 1_000_000);
  if (!normalizedAmount) throw new TypeError("invalid_refund_amount");
  const prior = await env.BODYMODE_DB.prepare(`
    SELECT account_key, removed_amount, remaining_debt
    FROM purchase_adjustments WHERE transaction_key = ?
  `).bind(transactionKey).first();
  if (prior) {
    return {
      adjusted: false,
      accountKey: prior.account_key == null ? null : String(prior.account_key),
      removedAmount: Number(prior.removed_amount || 0),
      remainingDebt: Number(prior.remaining_debt || 0),
    };
  }
  const lot = await env.BODYMODE_DB.prepare(`
    SELECT id, account_key, original_amount, remaining_amount
    FROM credit_lots WHERE transaction_key = ? AND source = 'purchase'
  `).bind(transactionKey).first();
  const now = unixTime();
  if (!lot) {
    await env.BODYMODE_DB.prepare(`
      INSERT INTO purchase_adjustments(
        transaction_key, account_key, original_amount, removed_amount,
        remaining_debt, status, adjusted_at
      ) VALUES (?, NULL, ?, 0, 0, 'refunded', ?)
    `).bind(transactionKey, normalizedAmount, now).run();
    return { adjusted: true, accountKey: null, removedAmount: 0, remainingDebt: 0 };
  }
  if (Number(lot.original_amount) !== normalizedAmount) {
    throw new CloudCreditError("refund_amount_conflict", 409, "返金対象のクレジット数が一致しません。");
  }
  const removed = Math.min(normalizedAmount, Number(lot.remaining_amount || 0));
  const debt = normalizedAmount - removed;
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(`
      UPDATE credit_lots SET remaining_amount = remaining_amount - ?
      WHERE id = ? AND remaining_amount >= ?
    `).bind(removed, lot.id, removed),
    env.BODYMODE_DB.prepare(`
      UPDATE credit_accounts SET available = available - ?, updated_at = ?
      WHERE account_key = ? AND available >= ?
    `).bind(removed, now, lot.account_key, removed),
    env.BODYMODE_DB.prepare(`
      INSERT INTO purchase_adjustments(
        transaction_key, account_key, original_amount, removed_amount,
        remaining_debt, status, adjusted_at
      ) VALUES (?, ?, ?, ?, ?, 'refunded', ?)
    `).bind(transactionKey, lot.account_key, normalizedAmount, removed, debt, now),
    env.BODYMODE_DB.prepare(`
      INSERT INTO credit_events(
        account_key, event_type, amount, source, feature, transaction_key, occurred_at
      ) VALUES (?, 'refund', ?, 'purchase', 'refund_adjustment', ?, ?)
    `).bind(lot.account_key, removed, transactionKey, now),
  ]);
  return {
    adjusted: true,
    accountKey: String(lot.account_key),
    removedAmount: removed,
    remainingDebt: debt,
  };
}

export async function reserveCredits(env, client, feature, requestID) {
  requireCreditAccount(client, env);
  await ensureCreditAccount(env, client);
  const costs = featureCosts(env);
  const cost = costs[feature];
  if (!cost) throw new CloudCreditError("unknown_ai_feature", 422, "AI機能を確認できませんでした。");
  if (!validRequestID(requestID)) {
    throw new CloudCreditError("invalid_request_id", 422, "リクエストIDを確認できませんでした。");
  }
  if (isUnlimitedClient(env, client)) {
    const now = unixTime();
    try {
      await env.BODYMODE_DB.prepare(`
        INSERT INTO ai_requests(
          request_id, account_key, feature, provider, model, status, created_at
        ) VALUES (?, ?, ?, 'openai', '', 'accepted', ?)
      `).bind(requestID, client.accountKey, feature, now).run();
    } catch (error) {
      const existing = await env.BODYMODE_DB.prepare(
        "SELECT status FROM ai_requests WHERE request_id = ?",
      ).bind(requestID).first();
      if (existing) {
        throw new CloudCreditError(
          "credit_request_conflict",
          409,
          existing.status === "accepted" ? "同じAI処理が実行中です。" : "同じAI処理は完了済みです。",
        );
      }
      throw error;
    }
    return {
      requestID,
      feature,
      cost: 0,
      unlimited: true,
      accountKey: client.accountKey,
    };
  }

  const existing = await env.BODYMODE_DB.prepare(
    "SELECT feature, cost, status FROM credit_reservations WHERE request_id = ?",
  ).bind(requestID).first();
  if (existing) {
    throw new CloudCreditError(
      "credit_request_conflict",
      409,
      existing.status === "pending" ? "同じAI処理が実行中です。" : "同じAI処理は完了済みです。",
    );
  }

  const now = unixTime();
  try {
    await env.BODYMODE_DB.batch([
      env.BODYMODE_DB.prepare(`
        INSERT INTO credit_reservations(request_id, account_key, feature, cost, status, created_at)
        SELECT ?, ?, ?, ?, 'pending', ?
        FROM credit_accounts
        WHERE account_key = ? AND available >= ?
      `).bind(requestID, client.accountKey, feature, cost, now, client.accountKey, cost),
      env.BODYMODE_DB.prepare(`
        UPDATE credit_accounts
        SET available = available - ?, reserved = reserved + ?, updated_at = ?
        WHERE account_key = ?
          AND EXISTS (
            SELECT 1 FROM credit_reservations
            WHERE request_id = ? AND status = 'pending'
          )
      `).bind(cost, cost, now, client.accountKey, requestID),
      env.BODYMODE_DB.prepare(`
        INSERT INTO credit_reservation_allocations(request_id, lot_id, amount)
        WITH ordered_lots AS (
          SELECT
            id,
            remaining_amount,
            COALESCE(SUM(remaining_amount) OVER (
              ORDER BY CASE source
                WHEN 'signup' THEN 0
                WHEN 'rewarded_ad' THEN 1
                WHEN 'purchase' THEN 2
                ELSE 3
              END, created_at, id
              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ), 0) AS consumed_before
          FROM credit_lots
          WHERE account_key = ? AND remaining_amount > 0
        )
        SELECT
          ?,
          id,
          MIN(remaining_amount, MAX(0, ? - consumed_before))
        FROM ordered_lots
        WHERE consumed_before < ?
          AND EXISTS (
            SELECT 1 FROM credit_reservations
            WHERE request_id = ? AND status = 'pending'
          )
      `).bind(client.accountKey, requestID, cost, cost, requestID),
      env.BODYMODE_DB.prepare(`
        UPDATE credit_lots
        SET remaining_amount = remaining_amount - COALESCE((
          SELECT amount FROM credit_reservation_allocations
          WHERE request_id = ? AND lot_id = credit_lots.id
        ), 0)
        WHERE id IN (
          SELECT lot_id FROM credit_reservation_allocations WHERE request_id = ?
        )
      `).bind(requestID, requestID),
      env.BODYMODE_DB.prepare(`
        INSERT INTO credit_events(
          account_key, event_type, amount, feature, request_id, occurred_at
        )
        SELECT ?, 'reserve', ?, ?, ?, ?
        WHERE EXISTS (
          SELECT 1 FROM credit_reservations
          WHERE request_id = ? AND status = 'pending'
        )
      `).bind(client.accountKey, cost, feature, requestID, now, requestID),
    ]);
  } catch (error) {
    const raced = await env.BODYMODE_DB.prepare(
      "SELECT status FROM credit_reservations WHERE request_id = ?",
    ).bind(requestID).first();
    if (raced) {
      throw new CloudCreditError("credit_request_conflict", 409, "同じAI処理がすでに受付済みです。");
    }
    throw error;
  }

  const reservation = await env.BODYMODE_DB.prepare(
    "SELECT feature, cost, status FROM credit_reservations WHERE request_id = ?",
  ).bind(requestID).first();
  if (!reservation) {
    const balance = await readBalance(env, client.accountKey);
    throw new CloudCreditError(
      "insufficient_ai_credits",
      402,
      "AIクレジットが不足しています。",
      { feature, cost, balance },
    );
  }
  return { requestID, feature, cost, unlimited: false };
}

export async function completeCreditReservation(env, reservation, usage = {}) {
  if (!reservation) return;
  const now = unixTime();
  if (reservation.unlimited) {
    await env.BODYMODE_DB.prepare(`
      UPDATE ai_requests
      SET model = ?, status = 'completed', input_tokens = ?, output_tokens = ?,
          duration_ms = ?, finished_at = ?
      WHERE request_id = ? AND account_key = ? AND status = 'accepted'
    `).bind(
      String(usage.model || ""),
      nonnegativeInteger(usage.inputTokens),
      nonnegativeInteger(usage.outputTokens),
      nonnegativeInteger(usage.durationMS),
      now,
      reservation.requestID,
      reservation.accountKey,
    ).run();
    return;
  }
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(`
      UPDATE credit_accounts
      SET reserved = reserved - ?, updated_at = ?
      WHERE account_key = (
        SELECT account_key FROM credit_reservations
        WHERE request_id = ? AND status = 'pending'
      ) AND reserved >= ?
    `).bind(reservation.cost, now, reservation.requestID, reservation.cost),
    env.BODYMODE_DB.prepare(`
      UPDATE credit_reservations
      SET status = 'completed', completed_at = ?
      WHERE request_id = ? AND status = 'pending'
    `).bind(now, reservation.requestID),
    env.BODYMODE_DB.prepare(
      "DELETE FROM credit_reservation_allocations WHERE request_id = ?",
    ).bind(reservation.requestID),
    env.BODYMODE_DB.prepare(`
      INSERT OR IGNORE INTO credit_events(
        account_key, event_type, amount, feature, request_id, occurred_at
      )
      SELECT account_key, 'spend', cost, feature, request_id, ?
      FROM credit_reservations WHERE request_id = ? AND status = 'completed'
    `).bind(now, reservation.requestID),
    env.BODYMODE_DB.prepare(`
      INSERT OR REPLACE INTO ai_requests(
        request_id, account_key, feature, provider, model, status,
        input_tokens, output_tokens, duration_ms, created_at, finished_at
      )
      SELECT request_id, account_key, feature, 'openai', ?, 'completed', ?, ?, ?, created_at, ?
      FROM credit_reservations WHERE request_id = ?
    `).bind(
      String(usage.model || ""),
      nonnegativeInteger(usage.inputTokens),
      nonnegativeInteger(usage.outputTokens),
      nonnegativeInteger(usage.durationMS),
      now,
      reservation.requestID,
    ),
  ]);
}

export async function releaseCreditReservation(env, reservation, errorCode = "ai_failed") {
  if (!reservation) return;
  const now = unixTime();
  if (reservation.unlimited) {
    await env.BODYMODE_DB.prepare(`
      UPDATE ai_requests
      SET status = 'failed', error_code = ?, finished_at = ?
      WHERE request_id = ? AND account_key = ? AND status = 'accepted'
    `).bind(
      String(errorCode).slice(0, 80),
      now,
      reservation.requestID,
      reservation.accountKey,
    ).run();
    return;
  }
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(`
      UPDATE credit_lots
      SET remaining_amount = remaining_amount + COALESCE((
        SELECT amount FROM credit_reservation_allocations
        WHERE request_id = ? AND lot_id = credit_lots.id
      ), 0)
      WHERE id IN (
        SELECT lot_id FROM credit_reservation_allocations
        WHERE request_id = ?
      ) AND EXISTS (
        SELECT 1 FROM credit_reservations
        WHERE request_id = ? AND status = 'pending'
      )
    `).bind(reservation.requestID, reservation.requestID, reservation.requestID),
    env.BODYMODE_DB.prepare(`
      UPDATE credit_accounts
      SET available = available + ?, reserved = reserved - ?, updated_at = ?
      WHERE account_key = (
        SELECT account_key FROM credit_reservations
        WHERE request_id = ? AND status = 'pending'
      ) AND reserved >= ?
    `).bind(reservation.cost, reservation.cost, now, reservation.requestID, reservation.cost),
    env.BODYMODE_DB.prepare(`
      UPDATE credit_reservations
      SET status = 'released', released_at = ?
      WHERE request_id = ? AND status = 'pending'
    `).bind(now, reservation.requestID),
    env.BODYMODE_DB.prepare(
      "DELETE FROM credit_reservation_allocations WHERE request_id = ?",
    ).bind(reservation.requestID),
    env.BODYMODE_DB.prepare(`
      INSERT OR IGNORE INTO credit_events(
        account_key, event_type, amount, feature, request_id, occurred_at
      )
      SELECT account_key, 'release', cost, feature, request_id, ?
      FROM credit_reservations WHERE request_id = ? AND status = 'released'
    `).bind(now, reservation.requestID),
    env.BODYMODE_DB.prepare(`
      INSERT OR REPLACE INTO ai_requests(
        request_id, account_key, feature, provider, model, status,
        error_code, created_at, finished_at
      )
      SELECT request_id, account_key, feature, 'openai', '', 'failed', ?, created_at, ?
      FROM credit_reservations WHERE request_id = ?
    `).bind(String(errorCode).slice(0, 80), now, reservation.requestID),
  ]);
}

export async function ensureCreditAccount(env, client) {
  requireDatabase(env);
  const now = unixTime();
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(`
      INSERT OR IGNORE INTO accounts(account_key, apple_subject_hash, created_at)
      VALUES (?, ?, ?)
    `).bind(client.accountKey, client.subject, now),
    env.BODYMODE_DB.prepare(`
      INSERT OR IGNORE INTO credit_accounts(account_key, available, reserved, updated_at)
      VALUES (?, 0, 0, ?)
    `).bind(client.accountKey, now),
  ]);
}

async function readBalance(env, accountKey) {
  const account = await env.BODYMODE_DB.prepare(
    "SELECT available, reserved FROM credit_accounts WHERE account_key = ?",
  ).bind(accountKey).first();
  const lots = await env.BODYMODE_DB.prepare(`
    SELECT source, COALESCE(SUM(remaining_amount), 0) AS amount
    FROM credit_lots WHERE account_key = ? AND remaining_amount > 0
    GROUP BY source
  `).bind(accountKey).all();
  const buckets = {};
  for (const row of lots?.results || []) buckets[String(row.source)] = Number(row.amount || 0);
  const available = Number(account?.available || 0);
  const reserved = Number(account?.reserved || 0);
  return { total: available + reserved, available, reserved, buckets };
}

function requireCreditAccount(client, env) {
  if (!client.isAppleAccount && !isUnlimitedClient(env, client)) {
    throw new CloudCreditError(
      "account_sign_in_required",
      403,
      "AI機能を使うにはAppleで登録してください。手動機能は登録なしで使えます。",
    );
  }
}

function signupBonus(env) {
  return boundedInteger(env.AI_CREDIT_SIGNUP_BONUS, 20, 0, 1_000);
}

function unlimitedAccountKeys(env) {
  return new Set(String(env.BODYMODE_UNLIMITED_ACCOUNT_KEYS || "")
    .split(",").map((value) => value.trim()).filter(Boolean));
}

function unlimitedSubjects(env) {
  return new Set(String(env.BODYMODE_UNLIMITED_SUBJECTS || "")
    .split(",").map((value) => value.trim()).filter(Boolean));
}

function validRequestID(value) {
  return /^[0-9a-fA-F-]{16,64}$/.test(String(value || ""));
}

function requireDatabase(env) {
  if (!env.BODYMODE_DB) {
    throw new CloudCreditError("cloud_database_not_configured", 503, "クラウド台帳を利用できません。");
  }
}

function unixTime() {
  return Math.floor(Date.now() / 1_000);
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(parsed, maximum));
}

function nonnegativeInteger(value) {
  const parsed = Number.parseInt(String(value ?? "0"), 10);
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}
