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
    old
      .prepare("INSERT INTO users VALUES(?,?,?,?,?,?)")
      .run("u", "u@example.com", "Student", "test-hash", "student", 1);
    old
      .prepare("INSERT INTO study_sets VALUES(?,?,?,?,?,?,?,?)")
      .run("s", "u", "Lecture", "Important notes", 1, 0, 1, 1);
    old
      .prepare("INSERT INTO questions VALUES(?,?,?,?,?,?,?,?,?)")
      .run(
        "q",
        "s",
        0,
        "Question",
        '["A","B","C","D"]',
        0,
        "Explanation",
        "easy",
        "Topic",
      );
    old
      .prepare("INSERT INTO quiz_attempts VALUES(?,?,?,?,?,?)")
      .run("attempt", "u", "s", 1, 1, 1);
    old
      .prepare("INSERT INTO quiz_answers VALUES(?,?,?)")
      .run("attempt", "q", 0);
    old.pragma("user_version=1");
    old.close();
    const { sqlite } = openDatabase(dir);
    assert.equal(sqlite.pragma("user_version", { simple: true }), 3);
    const material = sqlite
      .prepare("SELECT * FROM study_sets WHERE id=?")
      .get("s") as any;
    assert.equal(material.notes, "Important notes");
    assert.equal(material.version, 2);
    assert.equal(material.folder, "");
    assert.equal(
      (
        sqlite
          .prepare("SELECT collection_id FROM questions WHERE id=?")
          .get("q") as any
