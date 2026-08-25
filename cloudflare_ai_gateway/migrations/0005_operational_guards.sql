PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS api_rate_windows (
    scope TEXT NOT NULL,
    subject_key TEXT NOT NULL,
    window_started_at INTEGER NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0 CHECK(request_count >= 0),
    expires_at INTEGER NOT NULL,
    PRIMARY KEY(scope, subject_key, window_started_at)
);

CREATE INDEX IF NOT EXISTS idx_api_rate_windows_expiry
ON api_rate_windows(expires_at);

INSERT OR REPLACE INTO schema_metadata(key, value, updated_at)
VALUES ('schema_version', '5', unixepoch());
