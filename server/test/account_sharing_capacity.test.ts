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
test("forgot password: non-enumerating response, real delivery adapter, one-use expiry and revocation", async (t) => {
  const mail: { email: string; url: string }[] = [];
  const { call, register, advance } = await setup(t, {
    resetDelivery: async (email, url) => {
      mail.push({ email, url });
    },
  });
  const a = await register();
  const unknown = await call("POST", "/auth/forgot-password", undefined, {
    email: "unknown@example.com",
  });
  const known = await call("POST", "/auth/forgot-password", undefined, {
    email: "owner@example.com",
  });
  assert.deepEqual(known, unknown);
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.equal(mail.length, 1);
  const token = new URLSearchParams(new URL(mail[0].url).hash.slice(1)).get(
    "token",
  )!;
  assert.ok(token);
  assert.equal(
    (
      await call("POST", "/auth/reset-password", undefined, {
        token,
        password: "replacement-password",
      })
    ).status,
    200,
  );
  assert.equal((await call("GET", "/me", a.token)).status, 401);
  assert.equal(
    (
      await call("POST", "/auth/reset-password", undefined, {
        token,
        password: "reused-password",
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await call("POST", "/auth/login", undefined, {
        email: "owner@example.com",
        password: "replacement-password",
      })
    ).status,
    200,
  );
  advance(61000);
  await call("POST", "/auth/forgot-password", undefined, {
    email: "owner@example.com",
  });
  await new Promise((resolve) => setTimeout(resolve, 15));
  const expired = new URLSearchParams(new URL(mail[1].url).hash.slice(1)).get(
    "token",
  )!;
  advance(1200001);
  assert.equal(
    (
      await call("POST", "/auth/reset-password", undefined, {
        token: expired,
        password: "expired-password",
      })
    ).status,
    400,
  );
});
test("unconfigured reset delivery is explicit, never a fake sent email", async (t) => {
  const { call } = await setup(t);
  const response = await call("POST", "/auth/forgot-password", undefined, {
    email: "anyone@example.com",
  });
  assert.equal(response.body.deliveryAvailable, false);
});
test("public sharing is an explicit escaped snapshot, isolated, expiring and revocable", async (t) => {
  const { app, call, register, advance } = await setup(t);
  const a = await register(),
    b = await register("other@example.com");
  const set = (
