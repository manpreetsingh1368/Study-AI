CREATE TABLE notebook_entries(id TEXT PRIMARY KEY,notebook_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,kind TEXT NOT NULL,prompt TEXT NOT NULL,source_ids TEXT NOT NULL,request_hash TEXT NOT NULL,content TEXT NOT NULL,created_at INTEGER NOT NULL);
CREATE INDEX notebook_entries_recent ON notebook_entries(notebook_id,created_at DESC,id);
CREATE TABLE notebook_notes(id TEXT PRIMARY KEY,notebook_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,title TEXT NOT NULL,text TEXT NOT NULL,citations TEXT NOT NULL,created_at INTEGER NOT NULL,deleted INTEGER NOT NULL DEFAULT 0);
CREATE INDEX notebook_notes_recent ON notebook_notes(notebook_id,deleted,created_at DESC);
CREATE TABLE notebook_preferences(notebook_id TEXT PRIMARY KEY REFERENCES study_sets(id) ON DELETE CASCADE,source_ids TEXT NOT NULL);
-- Existing clients need a fresh material snapshot to receive notebook metadata.
INSERT INTO sync_changes(user_id,set_id,version,deleted) SELECT user_id,id,version,deleted FROM study_sets;

-- Receipts acknowledge operations; they must not retain private historical snapshots.
UPDATE mutation_receipts SET response=json_object('setId',json_extract(response,'$.setId'));
