PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS rewarded_ad_grants (
    transaction_id TEXT PRIMARY KEY,
    challenge_id TEXT NOT NULL UNIQUE,
    account_key TEXT NOT NULL,
    day_key TEXT NOT NULL,
    granted_amount INTEGER NOT NULL CHECK(granted_amount > 0),
    granted_at INTEGER NOT NULL,
    FOREIGN KEY(challenge_id) REFERENCES rewarded_ad_challenges(challenge_id) ON DELETE CASCADE,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rewarded_ad_grants_account_day
ON rewarded_ad_grants(account_key, day_key);

CREATE TRIGGER IF NOT EXISTS limit_rewarded_ad_grants_per_day
BEFORE INSERT ON rewarded_ad_grants
WHEN (
    SELECT COUNT(*) FROM rewarded_ad_grants
    WHERE account_key = NEW.account_key AND day_key = NEW.day_key
) >= 3
BEGIN
    SELECT RAISE(ABORT, 'rewarded_ad_daily_limit');
END;

INSERT OR REPLACE INTO schema_metadata(key, value, updated_at)
VALUES ('schema_version', '4', unixepoch());
