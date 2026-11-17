ALTER TABLE users ADD COLUMN password_enabled INTEGER NOT NULL DEFAULT 1;
ALTER TABLE sessions ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE study_sets ADD COLUMN parent_notebook_id TEXT REFERENCES study_sets(id) ON DELETE CASCADE;
CREATE INDEX study_sets_parent ON study_sets(parent_notebook_id,deleted);
CREATE TABLE password_resets(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,expires_at INTEGER NOT NULL,used_at INTEGER,created_at INTEGER NOT NULL);
