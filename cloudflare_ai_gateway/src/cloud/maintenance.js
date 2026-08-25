import { releaseCreditReservation } from "./credits.js";

export async function runCloudMaintenance(env) {
  if (!env.BODYMODE_DB) return { skipped: true };
  const now = unixTime();
  const staleBefore = now - boundedInteger(
    env.BODYMODE_STALE_RESERVATION_SECONDS,
    15 * 60,
    5 * 60,
    24 * 60 * 60,
  );
  const stale = await env.BODYMODE_DB.prepare(`
    SELECT request_id, feature, cost
    FROM credit_reservations
    WHERE status = 'pending' AND created_at < ?
    ORDER BY created_at
    LIMIT 100
  `).bind(staleBefore).all();
  let released = 0;
  for (const row of stale?.results || []) {
    await releaseCreditReservation(env, {
      requestID: String(row.request_id),
      feature: String(row.feature),
      cost: Number(row.cost),
      unlimited: false,
    }, "worker_interrupted");
    released += 1;
  }
  await env.BODYMODE_DB.batch([
    env.BODYMODE_DB.prepare(
      "DELETE FROM revoked_access_tokens WHERE expires_at <= ?",
    ).bind(now),
    env.BODYMODE_DB.prepare(
      "DELETE FROM anonymous_events WHERE expires_at <= ?",
    ).bind(now),
    env.BODYMODE_DB.prepare(
      "DELETE FROM api_rate_windows WHERE expires_at <= ?",
    ).bind(now),
    env.BODYMODE_DB.prepare(`
      UPDATE rewarded_ad_challenges SET status = 'expired'
      WHERE status = 'pending' AND expires_at <= ?
    `).bind(now),
  ]);
  return { skipped: false, released_reservations: released };
}

function unixTime() {
  return Math.floor(Date.now() / 1_000);
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(parsed, maximum));
}
