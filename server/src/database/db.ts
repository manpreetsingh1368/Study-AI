import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import * as schema from "./schema.js";
export function openDatabase(directory: string) {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const sqlite = new Database(join(directory, "study.sqlite"));
  sqlite.pragma("journal_mode = WAL");
  sqlite.pragma("foreign_keys = ON");
  sqlite.pragma("busy_timeout = 5000");
  const migrations = [
    "001_initial.sql",
    "002_learning_sync.sql",
    "003_recovery_and_generation.sql",
    "004_notebook_studio.sql",
    "005_identity_sharing_capacity.sql",
  ];
  const version = sqlite.pragma("user_version", { simple: true }) as number;
  if (version > migrations.length) {
    sqlite.close();
    throw new Error("Database schema is newer than this application.");
  }
  for (let i = version; i < migrations.length; i++) {
    sqlite.transaction(() => {
      sqlite.exec(
        readFileSync(
          new URL(`../../migrations/${migrations[i]}`, import.meta.url),
          "utf8",
        ),
      );
      sqlite.pragma(`user_version = ${i + 1}`);
    })();
  }
  return { sqlite, orm: drizzle(sqlite, { schema }) };
}
