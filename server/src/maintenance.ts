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
