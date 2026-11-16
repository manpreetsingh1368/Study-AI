import { test } from "node:test";
import assert from "node:assert/strict";
import Database from "better-sqlite3";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { openDatabase } from "../src/database/db.js";
test("v1 migration retains accounts, material, questions, attempts and emits a fresh sync snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "study-upgrade-"));
  try {
    const old = new Database(join(dir, "study.sqlite"));
    old.pragma("foreign_keys=ON");
    old.exec(
      readFileSync(
        new URL("../migrations/001_initial.sql", import.meta.url),
        "utf8",
      ),
    );
