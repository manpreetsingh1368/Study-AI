ALTER TABLE generation_usage ADD COLUMN request_hash TEXT;
ALTER TABLE generation_usage ADD COLUMN request_config TEXT;
ALTER TABLE generation_usage ADD COLUMN collection_id TEXT REFERENCES collections(id) ON DELETE SET NULL;
CREATE TABLE recovery_codes(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,code_hash TEXT NOT NULL UNIQUE,expires_at INTEGER NOT NULL,created_at INTEGER NOT NULL);
