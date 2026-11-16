import "dotenv/config";
import { openDatabase } from "./database/db.js";
import { existsSync, readdirSync, statSync, unlinkSync } from "node:fs";
import { join } from "node:path";
const { sqlite } = openDatabase(process.env.DATA_DIR || "./data");
const uploads = process.env.UPLOAD_DIR || "./uploads",
  now = Date.now();
const retention = Number(process.env.DELETED_FILE_RETENTION_DAYS || 30);
if (!Number.isFinite(retention) || retention < 1)
  throw new Error("Retention must be at least one day.");
try {
  const files = sqlite
    .prepare(
      "SELECT d.id FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE s.deleted=1 AND s.updated_at<?",
    )
    .all(now - retention * 86400000) as { id: string }[];
  // Clear private blobs before metadata: if interrupted, retrying unlink is safe.
  for (const file of files)
    if (existsSync(join(uploads, file.id))) unlinkSync(join(uploads, file.id));
  sqlite.transaction(() => {
    for (const file of files)
      sqlite.prepare("DELETE FROM documents WHERE id=?").run(file.id);
    sqlite
      .prepare(
        "UPDATE study_sets SET notes='',title='Deleted study set',folder='' WHERE deleted=1 AND updated_at<?",
      )
      .run(now - retention * 86400000);
    sqlite.prepare("DELETE FROM sessions WHERE expires_at<=?").run(now);
    sqlite.prepare("DELETE FROM recovery_codes WHERE expires_at<=?").run(now);
    sqlite
