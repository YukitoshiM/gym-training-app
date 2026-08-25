import { isUnlimitedClient } from "./credits.js";

export async function cloudOperationsStatus(env, client) {
  if (!isUnlimitedClient(env, client)) {
    const error = new Error("管理者だけが確認できます。");
    error.code = "admin_required";
    error.status = 403;
    throw error;
  }
  const now = Math.floor(Date.now() / 1_000);
  const since = now - 24 * 60 * 60;
  const staleBefore = now - 15 * 60;
  const [requests, durations, errors, pending, stalePending, creditAnomalies, grants, purchases, analytics] = await Promise.all([
    env.BODYMODE_DB.prepare(`
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
        COALESCE(ROUND(AVG(CASE WHEN status = 'completed' THEN duration_ms END)), 0) AS average_duration_ms,
        COALESCE(SUM(input_tokens), 0) AS input_tokens,
        COALESCE(SUM(output_tokens), 0) AS output_tokens
      FROM ai_requests WHERE created_at >= ?
    `).bind(since).first(),
    env.BODYMODE_DB.prepare(`
      SELECT duration_ms
      FROM ai_requests
      WHERE created_at >= ? AND status = 'completed' AND duration_ms IS NOT NULL
      ORDER BY duration_ms
    `).bind(since).all(),
    env.BODYMODE_DB.prepare(`
      SELECT error_code, COUNT(*) AS count
      FROM ai_requests
      WHERE created_at >= ? AND status = 'failed'
      GROUP BY error_code ORDER BY count DESC, error_code LIMIT 10
    `).bind(since).all(),
    env.BODYMODE_DB.prepare(`
      SELECT COUNT(*) AS count, COALESCE(SUM(cost), 0) AS credits
      FROM credit_reservations WHERE status = 'pending'
    `).first(),
    env.BODYMODE_DB.prepare(`
      SELECT COUNT(*) AS count, COALESCE(SUM(cost), 0) AS credits
      FROM credit_reservations
      WHERE status = 'pending' AND created_at < ?
    `).bind(staleBefore).first(),
    env.BODYMODE_DB.prepare(`
      SELECT COUNT(*) AS count
      FROM credit_accounts AS account
      WHERE account.available < 0
         OR account.reserved < 0
         OR account.available + account.reserved != COALESCE((
           SELECT SUM(lot.remaining_amount)
           FROM credit_lots AS lot
           WHERE lot.account_key = account.account_key
         ), 0)
    `).first(),
    env.BODYMODE_DB.prepare(`
      SELECT COUNT(*) AS count, COALESCE(SUM(granted_amount), 0) AS credits
      FROM rewarded_ad_grants WHERE granted_at >= ?
    `).bind(since).first(),
    env.BODYMODE_DB.prepare(`
      SELECT
        SUM(CASE WHEN status = 'processed' THEN 1 ELSE 0 END) AS processed,
        SUM(CASE WHEN status = 'rejected' THEN 1 ELSE 0 END) AS rejected
      FROM webhook_events WHERE received_at >= ?
    `).bind(since).first(),
    env.BODYMODE_DB.prepare(
      "SELECT COUNT(*) AS count FROM anonymous_events WHERE occurred_at >= ?",
    ).bind(since).first(),
  ]);
  const total = Number(requests?.total || 0);
  const completed = Number(requests?.completed || 0);
  const failed = Number(requests?.failed || 0);
  const successRate = total ? Number((completed / total).toFixed(4)) : null;
  const durationValues = (durations?.results || []).map((row) => Number(row.duration_ms || 0));
  const p95Duration = percentile(durationValues, 0.95);
  const dailyLimit = positiveInteger(env.BODYMODE_AI_GLOBAL_DAILY_LIMIT, 500);
  const dailyUtilization = dailyLimit ? Number((total / dailyLimit).toFixed(4)) : null;
  const rejectedNotifications = Number(purchases?.rejected || 0);
  const staleReservationCount = Number(stalePending?.count || 0);
  const anomalyCount = Number(creditAnomalies?.count || 0);
  const alerts = operationalAlerts({
    total,
    successRate,
    p95Duration,
    dailyUtilization,
    staleReservationCount,
    anomalyCount,
    rejectedNotifications,
  });
  return {
    generated_at: new Date().toISOString(),
    window_hours: 24,
    ai: {
      total,
      completed,
      failed,
      success_rate: successRate,
      average_duration_ms: Number(requests?.average_duration_ms || 0),
      p95_duration_ms: p95Duration,
      input_tokens: Number(requests?.input_tokens || 0),
      output_tokens: Number(requests?.output_tokens || 0),
      daily_request_limit: dailyLimit,
      daily_request_utilization: dailyUtilization,
      errors: (errors?.results || []).map((row) => ({
        code: String(row.error_code || "unknown"), count: Number(row.count || 0),
      })),
    },
    credits: {
      pending_reservations: Number(pending?.count || 0),
      pending_credits: Number(pending?.credits || 0),
      stale_pending_reservations: staleReservationCount,
      stale_pending_credits: Number(stalePending?.credits || 0),
      invariant_anomalies: anomalyCount,
    },
    rewarded_ads: {
      grants: Number(grants?.count || 0),
      credits: Number(grants?.credits || 0),
    },
    app_store_notifications: {
      processed: Number(purchases?.processed || 0),
      rejected: rejectedNotifications,
    },
    analytics_events: Number(analytics?.count || 0),
    alerts,
    status: alerts.some((alert) => alert.severity === "critical")
      ? "critical"
      : alerts.length ? "warning" : "ok",
  };
}

export function percentile(values, ratio) {
  if (!values.length) return 0;
  const index = Math.max(0, Math.ceil(values.length * ratio) - 1);
  return Number(values[index] || 0);
}

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function operationalAlerts({
  total,
  successRate,
  p95Duration,
  dailyUtilization,
  staleReservationCount,
  anomalyCount,
  rejectedNotifications,
}) {
  const alerts = [];
  if (total >= 10 && successRate < 0.9) {
    alerts.push(alert("critical", "ai_error_rate_high", "AI成功率が90%未満です。"));
  } else if (total >= 10 && successRate < 0.95) {
    alerts.push(alert("warning", "ai_error_rate_elevated", "AI成功率が95%未満です。"));
  }
  if (p95Duration > 100_000) {
    alerts.push(alert("critical", "ai_p95_too_slow", "AI応答p95が100秒を超えています。"));
  } else if (p95Duration > 60_000) {
    alerts.push(alert("warning", "ai_p95_slow", "AI応答p95が60秒を超えています。"));
  }
  if (dailyUtilization >= 1) {
    alerts.push(alert("critical", "ai_daily_limit_reached", "AI日次上限に到達しています。"));
  } else if (dailyUtilization >= 0.8) {
    alerts.push(alert("warning", "ai_daily_limit_near", "AI日次上限の80%を超えています。"));
  }
  if (staleReservationCount > 0) {
    alerts.push(alert("critical", "stale_credit_reservation", "15分を超える未確定クレジットがあります。"));
  }
  if (anomalyCount > 0) {
    alerts.push(alert("critical", "credit_invariant_failed", "クレジット残高の整合性エラーがあります。"));
  }
  if (rejectedNotifications > 0) {
    alerts.push(alert("warning", "app_store_notification_rejected", "拒否されたApp Store通知があります。"));
  }
  return alerts;
}

function alert(severity, code, message) {
  return { severity, code, message };
}
