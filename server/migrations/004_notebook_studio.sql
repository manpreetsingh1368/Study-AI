CREATE TABLE notebook_entries(id TEXT PRIMARY KEY,notebook_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,kind TEXT NOT NULL,prompt TEXT NOT NULL,source_ids TEXT NOT NULL,request_hash TEXT NOT NULL,content TEXT NOT NULL,created_at INTEGER NOT NULL);
CREATE INDEX notebook_entries_recent ON notebook_entries(notebook_id,created_at DESC,id);
