import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import Database from "better-sqlite3";
import { createApp } from "../src/app.js";
import { outputSchema } from "../src/ai/gemini.js";
const fixture = {
  questions: [
    {
      question: "What is ATP?",
      choices: ["Energy carrier", "DNA", "Water", "Salt"],
      answer: 0,
      explanation: "ATP carries chemical energy.",
      difficulty: "medium" as const,
      topic: "Biology",
    },
  ],
  flashcards: [
    {
      front: "ATP",
      back: "Energy carrier",
      topic: "Biology",
      difficulty: "medium" as const,
    },
  ],
};
async function setup(t: any) {
  const dir = mkdtempSync(join(tmpdir(), "study-test-"));
  let clock = Date.now();
  const app = createApp({
    dataDir: dir,
    uploadDir: join(dir, "uploads"),
    now: () => clock,
    generate: async () => fixture,
  });
  await app.ready();
  t.after(async () => {
    await app.close();
    rmSync(dir, { recursive: true, force: true });
  });
  async function call(method: any, url: string, token?: string, payload?: any) {
    const r = await app.inject({
      method,
      url,
      headers: token ? { authorization: `Bearer ${token}` } : {},
      payload,
    });
    return { status: r.statusCode, body: r.json() };
  }
  async function register(email = "student@example.com") {
    return (
      await call("POST", "/auth/register", undefined, {
        name: "Student",
        email,
        password: "very-secure-password",
      })
    ).body;
  }
  return { dir, app, call, register, advance: (ms: number) => (clock += ms) };
}
test("authentication, isolation, revocation, expiry and deletion", async (t) => {
  const { call, register, advance } = await setup(t);
  const a = await register(),
    b = await register("other@example.com");
  assert.equal((await call("GET", "/me")).status, 401);
  assert.equal(
    (
      await call("POST", "/auth/login", undefined, {
        email: "student@example.com",
        password: "wrong-password",
      })
    ).status,
    401,
  );
  const s = (
    await call("POST", "/sets", a.token, { title: "Biology", notes: "ATP" })
  ).body.set;
  assert.equal(
    (
      await call("PATCH", `/sets/${s.id}`, b.token, {
        title: "Stolen",
        notes: "",
        version: 1,
      })
    ).status,
    404,
  );
  assert.equal((await call("GET", "/admin/users", a.token)).status, 403);
  await call("POST", "/auth/logout", a.token);
  assert.equal((await call("GET", "/me", a.token)).status, 401);
  const login = (
    await call("POST", "/auth/login", undefined, {
      email: "student@example.com",
      password: "very-secure-password",
    })
  ).body;
  advance(31 * 86400000);
  assert.equal((await call("GET", "/me", login.token)).status, 401);
  const fresh = (
    await call("POST", "/auth/login", undefined, {
      email: "other@example.com",
      password: "very-secure-password",
    })
  ).body;
  assert.equal(
    (
      await call("DELETE", "/me", fresh.token, {
        password: "very-secure-password",
      })
    ).status,
    200,
  );
  assert.equal((await call("GET", "/me", fresh.token)).status, 401);
});
test("two devices: incremental sync, stale edit conflict and deletion tombstones", async (t) => {
  const { call, register } = await setup(t);
  const a = await register();
  const b = (
    await call("POST", "/auth/login", undefined, {
      email: "student@example.com",
      password: "very-secure-password",
    })
  ).body;
  const s = (
    await call("POST", "/sets", a.token, { title: "Device A", notes: "notes" })
  ).body.set;
  const page = (await call("GET", "/sync?cursor=0&limit=1", b.token)).body;
  assert.equal(page.changes[0].set.id, s.id);
  const edited = (
    await call("PATCH", `/sets/${s.id}`, b.token, {
      title: "Device B edit",
      notes: "updated",
      version: 1,
    })
  ).body.set;
  assert.equal(edited.version, 2);
  assert.equal(
    (
      await call("PATCH", `/sets/${s.id}`, a.token, {
        title: "Stale",
        notes: "old",
        version: 1,
      })
    ).status,
    409,
  );
  const delta = (await call("GET", `/sync?cursor=${page.cursor}`, a.token))
    .body;
  assert.equal(delta.changes[0].set.title, "Device B edit");
  assert.equal(
    (await call("DELETE", `/sets/${s.id}`, a.token, { version: 2 })).status,
    200,
  );
  const deleted = (await call("GET", `/sync?cursor=${delta.cursor}`, b.token))
    .body;
  assert.equal(deleted.changes[0].deleted, 1);
  assert.equal(deleted.changes[0].set, null);
  assert.equal(
    (
      await call("PATCH", `/sets/${s.id}`, b.token, {
        title: "Resurrection",
        notes: "",
        version: 3,
      })
    ).status,
    404,
  );
  assert.equal((await call("GET", "/sets", b.token)).body.sets.length, 0);
  const freshDevice = (await call("GET", "/sync?cursor=0&limit=1", b.token))
    .body;
  assert.equal(freshDevice.changes[0].set, null);
  assert.equal(freshDevice.changes[0].deleted, 1);
});
test("AI schemas, server scoring, offline replay idempotency and review intervals", async (t) => {
  const { call, register } = await setup(t);
  const a = await register();
  assert.equal(
    outputSchema.safeParse({
      questions: [{ ...fixture.questions[0], answer: 4 }],
      flashcards: [],
    }).success,
    false,
  );
  const sid = (
    await call("POST", "/sets", a.token, {
      title: "Quiz",
      notes: "ATP carries energy.",
    })
  ).body.set.id;
  const generated = await call("POST", `/sets/${sid}/generate`, a.token, {
    kind: "quiz",
    count: 1,
    difficulty: "medium",
  });
  assert.equal(generated.status, 200);
  const q = generated.body.set.questions[0];
  const payload = {
    id: randomUUID(),
    setId: sid,
    answers: { [q.id]: 1 },
    score: 999,
  };
  const attempt = (await call("POST", "/attempts", a.token, payload)).body
    .attempt;
  assert.equal(attempt.score, 0);
  assert.equal(
    (await call("POST", "/attempts", a.token, payload)).body.attempt.id,
    attempt.id,
  );
  const cards = (
    await call("POST", `/sets/${sid}/generate`, a.token, {
      kind: "flashcards",
      count: 1,
      difficulty: "medium",
    })
  ).body.set.flashcards;
  const review = { id: randomUUID(), cardId: cards[0].id, known: true };
  assert.equal(
    (await call("POST", "/reviews", a.token, review)).body.review.interval_days,
    1,
  );
  await call("POST", "/reviews", a.token, review);
  assert.equal(
    (await call("POST", "/reviews", a.token, { ...review, id: randomUUID() }))
      .body.review.interval_days,
    2,
  );
  assert.equal((await call("GET", "/analytics", a.token)).body.completed, 1);
  assert.equal((await call("GET", "/analytics", a.token)).body.reviewed, 2);
});
test("atomic concurrent quota, free restrictions, admin grant and expiry", async (t) => {
  const { call, register, dir, advance } = await setup(t);
  const a = await register();
  const db = new Database(join(dir, "study.sqlite"));
  db.prepare("UPDATE users SET role='admin' WHERE id=?").run(a.user.id);
  db.close();
  const b = await register("learner@example.com");
  const ids = [];
  for (let i = 0; i < 5; i++)
    ids.push(
      (
        await call("POST", "/sets", b.token, {
          title: `Set ${i}`,
          notes: "ATP",
        })
      ).body.set.id,
    );
  assert.equal(
    (await call("POST", "/sets", b.token, { title: "Sixth", notes: "" }))
      .status,
    403,
  );
  assert.equal(
    (
      await call("POST", `/sets/${ids[0]}/generate`, b.token, {
        kind: "exam",
        count: 1,
        difficulty: "medium",
      })
    ).status,
    403,
  );
  const results = await Promise.all(
    ids.map((sid) =>
      call("POST", `/sets/${sid}/generate`, b.token, {
        kind: "quiz",
        count: 1,
        difficulty: "medium",
      }),
    ),
  );
  assert.equal(results.filter((r) => r.status === 200).length, 3);
  assert.equal(results.filter((r) => r.status === 429).length, 2);
  assert.equal(
    (
      await call("PUT", `/admin/users/${b.user.id}/pro`, b.token, {
        enabled: true,
        expiresAt: Date.now() + 10000,
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await call("PUT", `/admin/users/${b.user.id}/pro`, a.token, {
        enabled: true,
        expiresAt: Date.now() + 10000,
      })
    ).status,
    200,
  );
  assert.equal((await call("GET", "/me", b.token)).body.plan.pro, true);
  advance(11000);
  assert.equal((await call("GET", "/me", b.token)).body.plan.pro, false);
});
test("private PDF upload signature validation and download authorization", async (t) => {
  const { app, call, register } = await setup(t);
  const a = await register(),
    b = await register("other@example.com");
  const sid = (
    await call("POST", "/sets", a.token, { title: "PDF", notes: "" })
  ).body.set.id;
  async function upload(content: string) {
    return app.inject({
      method: "POST",
      url: `/sets/${sid}/pdf`,
      headers: {
        authorization: `Bearer ${a.token}`,
        "content-type": "multipart/form-data; boundary=study",
      },
      payload: `--study\r\nContent-Disposition: form-data; name="file"; filename="notes.pdf"\r\nContent-Type: application/pdf\r\n\r\n${content}\r\n--study--\r\n`,
    });
  }
  assert.equal((await upload("not a PDF")).statusCode, 400);
  const pdf = await upload("%PDF-1.4\n%%EOF");
  assert.equal(pdf.statusCode, 200);
  const did = pdf.json().set.document.id;
  assert.equal(
    (
      await app.inject({
        method: "GET",
        url: `/documents/${did}`,
        headers: { authorization: `Bearer ${b.token}` },
      })
    ).statusCode,
    404,
  );
  assert.equal(
    (
      await app.inject({
        method: "GET",
        url: `/documents/${did}`,
        headers: { authorization: `Bearer ${a.token}` },
      })
    ).statusCode,
    200,
  );
});
test("restart persists accounts/materials; password change revokes every device session", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "study-restart-"));
  let app = createApp({ dataDir: dir, uploadDir: join(dir, "uploads") });
  t.after(async () => {
    await app.close();
    rmSync(dir, { recursive: true, force: true });
  });
  await app.ready();
  const reg = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: {
      name: "Restart",
      email: "restart@example.com",
      password: "initial-password",
    },
  });
  const token = reg.json().token;
  await app.inject({
    method: "POST",
    url: "/sets",
    headers: { authorization: `Bearer ${token}` },
    payload: { title: "Persistent", notes: "Saved" },
  });
  await app.close();
  app = createApp({ dataDir: dir, uploadDir: join(dir, "uploads") });
  await app.ready();
  const sets = await app.inject({
    method: "GET",
    url: "/sets",
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(sets.json().sets[0].title, "Persistent");
  const second = await app.inject({
    method: "POST",
    url: "/auth/login",
    payload: { email: "restart@example.com", password: "initial-password" },
  });
  const change = await app.inject({
    method: "POST",
    url: "/me/password",
    headers: { authorization: `Bearer ${token}` },
    payload: { current: "initial-password", password: "replacement-password" },
  });
  assert.equal(change.statusCode, 200);
  for (const revoked of [token, second.json().token])
    assert.equal(
      (
        await app.inject({
          method: "GET",
          url: "/me",
          headers: { authorization: `Bearer ${revoked}` },
        })
      ).statusCode,
      401,
    );
  assert.equal(
    (
      await app.inject({
        method: "POST",
        url: "/auth/login",
        payload: {
          email: "restart@example.com",
          password: "replacement-password",
        },
      })
    ).statusCode,
    200,
  );
});
