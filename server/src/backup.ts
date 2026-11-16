import "dotenv/config";
import { openDatabase } from "./database/db.js";
import { mkdirSync, cpSync, chmodSync } from "node:fs";
import { join } from "node:path";
// Stop the API before invoking so document files and the database form a consistent snapshot.
const destination = process.argv[2];
if (!destination)
  throw new Error("Usage: npm run backup -- /private/backup-directory");
mkdirSync(destination, { recursive: true, mode: 0o700 });
const { sqlite } = openDatabase(process.env.DATA_DIR || "./data");
await sqlite.backup(join(destination, "study.sqlite"));
sqlite.close();
chmodSync(join(destination, "study.sqlite"), 0o600);
cpSync(process.env.UPLOAD_DIR || "./uploads", join(destination, "uploads"), {
  recursive: true,
});
console.log(
  "Backup completed. Protect this directory: it contains private student data.",
);
