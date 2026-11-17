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
  extra: Partial<Parameters<typeof createApp>[0]> = {},
) {
  const directory = mkdtempSync(join(tmpdir(), "study-account-"));
  let clock = Date.now();
  const app = createApp({
    dataDir: directory,
    uploadDir: join(directory, "uploads"),
    now: () => clock,
    ...extra,
  });
  await app.ready();
  t.after(async () => {
    await app.close();
    rmSync(directory, { recursive: true, force: true });
  });
  async function call(method: any, url: string, token?: string, payload?: any) {
    const result = await app.inject({
      method,
      url,
      headers: token ? { authorization: `Bearer ${token}` } : {},
      payload,
    });
    return { status: result.statusCode, body: result.json() };
  }
  async function register(email = "owner@example.com") {
    return (
      await call("POST", "/auth/register", undefined, {
        name: "Owner",
        email,
        password: "owner-secure-password",
      })
    ).body;
  }
  return {
    app,
    call,
    register,
    directory,
    advance: (time: number) => (clock += time),
  };
}
