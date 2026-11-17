import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID, createHash } from "node:crypto";
import Database from "better-sqlite3";
import { PDFDocument } from "pdf-lib";
import { createApp } from "../src/app.js";
import type { OAuthAdapter } from "../src/security/oauth.js";
const digest = (s: string) => createHash("sha256").update(s).digest("hex");
async function setup(
  t: any,
