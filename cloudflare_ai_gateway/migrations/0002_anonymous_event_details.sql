ALTER TABLE anonymous_events ADD COLUMN dimension TEXT NOT NULL DEFAULT '';
ALTER TABLE anonymous_events ADD COLUMN properties_json TEXT NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_anonymous_events_name_occurred
ON anonymous_events(event_name, occurred_at DESC);

INSERT OR REPLACE INTO schema_metadata(key, value, updated_at)
VALUES ('schema_version', '2', unixepoch());
