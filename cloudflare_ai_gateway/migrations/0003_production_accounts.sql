PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS apple_refresh_tokens (
    token_id TEXT PRIMARY KEY,
    account_key TEXT NOT NULL,
    encrypted_token TEXT NOT NULL,
    initialization_vector TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_apple_refresh_tokens_account
ON apple_refresh_tokens(account_key, created_at);

CREATE TABLE IF NOT EXISTS rewarded_ad_challenges (
    challenge_id TEXT PRIMARY KEY,
    account_key TEXT NOT NULL,
    custom_data TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK(status IN ('pending', 'verified', 'granted', 'rejected', 'expired')),
    transaction_id TEXT UNIQUE,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    verified_at INTEGER,
    granted_at INTEGER,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rewarded_challenges_account_created
ON rewarded_ad_challenges(account_key, created_at DESC);

CREATE TABLE IF NOT EXISTS purchase_adjustments (
    transaction_key TEXT PRIMARY KEY,
    account_key TEXT,
    original_amount INTEGER NOT NULL,
    removed_amount INTEGER NOT NULL DEFAULT 0,
    remaining_debt INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL CHECK(status IN ('refunded', 'revoked')),
    adjusted_at INTEGER NOT NULL,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS webhook_events (
    event_key TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    received_at INTEGER NOT NULL,
    processed_at INTEGER,
    status TEXT NOT NULL CHECK(status IN ('received', 'processed', 'rejected'))
);

INSERT OR REPLACE INTO schema_metadata(key, value, updated_at)
VALUES ('schema_version', '3', unixepoch());
