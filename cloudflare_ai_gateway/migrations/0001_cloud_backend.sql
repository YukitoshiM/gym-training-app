PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
    account_key TEXT PRIMARY KEY,
    apple_subject_hash TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS revoked_access_tokens (
    token_id TEXT PRIMARY KEY,
    account_key TEXT,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER NOT NULL,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_revoked_access_tokens_expiry
ON revoked_access_tokens(expires_at);

CREATE TABLE IF NOT EXISTS credit_accounts (
    account_key TEXT PRIMARY KEY,
    available INTEGER NOT NULL DEFAULT 0 CHECK(available >= 0),
    reserved INTEGER NOT NULL DEFAULT 0 CHECK(reserved >= 0),
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS credit_lots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_key TEXT NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('signup', 'rewarded_ad', 'purchase', 'admin')),
    original_amount INTEGER NOT NULL CHECK(original_amount > 0),
    remaining_amount INTEGER NOT NULL CHECK(remaining_amount >= 0),
    transaction_key TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    expires_at INTEGER,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_credit_lots_spend_order
ON credit_lots(account_key, expires_at, created_at, id);

CREATE TABLE IF NOT EXISTS credit_reservations (
    request_id TEXT PRIMARY KEY,
    account_key TEXT NOT NULL,
    feature TEXT NOT NULL,
    cost INTEGER NOT NULL CHECK(cost > 0),
    status TEXT NOT NULL CHECK(status IN ('pending', 'completed', 'released')),
    created_at INTEGER NOT NULL,
    completed_at INTEGER,
    released_at INTEGER,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_credit_reservations_account_created
ON credit_reservations(account_key, created_at DESC);

CREATE TABLE IF NOT EXISTS credit_reservation_allocations (
    request_id TEXT NOT NULL,
    lot_id INTEGER NOT NULL,
    amount INTEGER NOT NULL CHECK(amount > 0),
    PRIMARY KEY(request_id, lot_id),
    FOREIGN KEY(request_id) REFERENCES credit_reservations(request_id) ON DELETE CASCADE,
    FOREIGN KEY(lot_id) REFERENCES credit_lots(id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS credit_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_key TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK(event_type IN ('grant', 'reserve', 'spend', 'release', 'refund')),
    amount INTEGER NOT NULL CHECK(amount >= 0),
    source TEXT,
    feature TEXT,
    request_id TEXT,
    transaction_key TEXT,
    occurred_at INTEGER NOT NULL,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_events_request_type
ON credit_events(request_id, event_type)
WHERE request_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_events_transaction_type
ON credit_events(transaction_key, event_type)
WHERE transaction_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS ai_requests (
    request_id TEXT PRIMARY KEY,
    account_key TEXT NOT NULL,
    feature TEXT NOT NULL,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('accepted', 'completed', 'failed', 'cancelled')),
    input_tokens INTEGER,
    output_tokens INTEGER,
    duration_ms INTEGER,
    error_code TEXT,
    created_at INTEGER NOT NULL,
    finished_at INTEGER,
    FOREIGN KEY(account_key) REFERENCES accounts(account_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ai_requests_account_created
ON ai_requests(account_key, created_at DESC);

CREATE TABLE IF NOT EXISTS food_sources (
    source_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    region TEXT NOT NULL,
    version TEXT NOT NULL,
    source_url TEXT NOT NULL,
    license TEXT NOT NULL,
    imported_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS foods (
    food_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    source_food_id TEXT NOT NULL,
    locale TEXT NOT NULL,
    canonical_name TEXT NOT NULL,
    calories_per_100g REAL,
    protein_per_100g REAL,
    fat_per_100g REAL,
    carbs_per_100g REAL,
    serving_grams REAL,
    data_quality TEXT NOT NULL DEFAULT 'reference',
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(source_id) REFERENCES food_sources(source_id) ON DELETE RESTRICT,
    UNIQUE(source_id, source_food_id)
);

CREATE INDEX IF NOT EXISTS idx_foods_locale_name
ON foods(locale, canonical_name);

CREATE TABLE IF NOT EXISTS food_aliases (
    normalized_alias TEXT NOT NULL,
    locale TEXT NOT NULL,
    food_id TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(normalized_alias, locale, food_id),
    FOREIGN KEY(food_id) REFERENCES foods(food_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_food_alias_lookup
ON food_aliases(locale, normalized_alias, priority DESC);

CREATE TABLE IF NOT EXISTS public_barcode_products (
    barcode TEXT NOT NULL,
    region TEXT NOT NULL,
    food_id TEXT NOT NULL,
    brand TEXT,
    product_name TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(barcode, region),
    FOREIGN KEY(food_id) REFERENCES foods(food_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS evidence_documents (
    document_id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    title TEXT NOT NULL,
    abstract TEXT,
    source_url TEXT NOT NULL,
    publication_date TEXT,
    license TEXT,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence_chunks (
    chunk_id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    content TEXT NOT NULL,
    purpose_tags TEXT NOT NULL DEFAULT '[]',
    population_tags TEXT NOT NULL DEFAULT '[]',
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(document_id) REFERENCES evidence_documents(document_id) ON DELETE CASCADE,
    UNIQUE(document_id, ordinal)
);

CREATE TABLE IF NOT EXISTS anonymous_events (
    event_id TEXT PRIMARY KEY,
    installation_key TEXT NOT NULL,
    event_name TEXT NOT NULL,
    app_version TEXT NOT NULL,
    locale TEXT NOT NULL,
    distribution_channel TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_anonymous_events_expiry
ON anonymous_events(expires_at);

INSERT OR REPLACE INTO schema_metadata(key, value, updated_at)
VALUES ('schema_version', '1', unixepoch());
