ALTER TABLE generation_usage ADD COLUMN request_hash TEXT;
ALTER TABLE generation_usage ADD COLUMN request_config TEXT;
ALTER TABLE generation_usage ADD COLUMN collection_id TEXT REFERENCES collections(id) ON DELETE SET NULL;
