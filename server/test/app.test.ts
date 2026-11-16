import { PDFDocument } from "pdf-lib";
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
  async function upload(content: string | Buffer) {
    return app.inject({
      method: "POST",
      url: `/sets/${sid}/pdf`,
      headers: {
        authorization: `Bearer ${a.token}`,
        "content-type": "multipart/form-data; boundary=study",
      },
      payload: Buffer.concat([
        Buffer.from(
          '--study\r\nContent-Disposition: form-data; name="file"; filename="notes.pdf"\r\nContent-Type: application/pdf\r\n\r\n',
        ),
        Buffer.isBuffer(content) ? content : Buffer.from(content),
        Buffer.from("\r\n--study--\r\n"),
      ]),
    });
  }
  assert.equal((await upload("not a PDF")).statusCode, 400);
  assert.equal((await upload("%PDF-1.4\n%%EOF")).statusCode, 400);
  const document = await PDFDocument.create();
  document.addPage();
  const pdf = await upload(Buffer.from(await document.save()));
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
test("offline mutation receipts, version conflicts, folders and no resurrection", async (t) => {
  const { call, register } = await setup(t);
  const a = await register(),
    b = await register("other@example.com");
  const sid = randomUUID(),
    op = {
      id: randomUUID(),
      kind: "create",
      setId: sid,
      baseVersion: 0,
      title: "Offline notes",
      notes: "Original",
      folder: "Biology",
    };
  const created = await call("POST", "/sync/mutate", a.token, op);
  assert.equal(created.status, 200);
  assert.equal(created.body.set.folder, "Biology");
  assert.equal(
    (await call("POST", "/sync/mutate", a.token, op)).body.set.version,
    1,
  );
  assert.equal(
    (await call("POST", "/sync/mutate", a.token, { ...op, title: "Different" }))
      .status,
    409,
  );
  assert.equal(
    (
      await call("POST", "/sync/mutate", b.token, {
        ...op,
        id: randomUUID(),
        kind: "update",
        baseVersion: 1,
      })
    ).status,
    404,
  );
  const update = {
    ...op,
    id: randomUUID(),
    kind: "update",
    baseVersion: 1,
    notes: "Device B",
  };
  assert.equal(
    (await call("POST", "/sync/mutate", a.token, update)).body.set.version,
    2,
  );
  assert.equal(
    (
      await call("POST", "/sync/mutate", a.token, {
        ...update,
        id: randomUUID(),
        notes: "Stale edit",
      })
    ).status,
    409,
  );
  const deletion = { ...op, id: randomUUID(), kind: "delete", baseVersion: 2 };
  assert.equal(
    (await call("POST", "/sync/mutate", a.token, deletion)).body.set,
    null,
  );
  assert.equal(
    (await call("POST", "/sync/mutate", a.token, deletion)).status,
    200,
  );
  assert.equal(
    (await call("POST", "/sync/mutate", a.token, { ...op, id: randomUUID() }))
      .status,
    409,
  );
});
test("immutable collections, historical review, learning deltas and timed exam enforcement", async (t) => {
  const { call, register, dir, advance } = await setup(t);
  const a = await register(),
    b = await register("other@example.com");
  const db = new Database(join(dir, "study.sqlite"));
  db.prepare("INSERT INTO subscriptions VALUES(?,?,?)").run(
    a.user.id,
    Date.now() - 1000,
    Date.now() + 86400000,
  );
  db.close();
  const sid = (
    await call("POST", "/sets", a.token, {
      title: "Many collections",
      notes: "ATP",
    })
  ).body.set.id;
  let set = (
    await call("POST", `/sets/${sid}/generate`, a.token, {
      kind: "quiz",
      count: 1,
      difficulty: "medium",
    })
  ).body.set;
  const first = set.collections[0];
  const q = set.questions[0];
  const attemptId = randomUUID();
  assert.equal(
    (
      await call("POST", "/attempts", a.token, {
        id: attemptId,
        setId: sid,
        collectionId: first.id,
        answers: { [q.id]: 0 },
      })
    ).body.attempt.score,
    1,
  );
  set = (
    await call("POST", `/sets/${sid}/generate`, a.token, {
      kind: "quiz",
      count: 1,
      difficulty: "medium",
    })
  ).body.set;
  assert.equal(set.collections.length, 2);
  const history = (await call("GET", `/attempts/${attemptId}`, a.token)).body
    .attempt;
  assert.equal(history.questions.length, 1);
  assert.equal(history.questions[0].selected, 0);
  assert.equal(
    (await call("GET", `/attempts/${attemptId}`, b.token)).status,
    404,
  );
  const delta = (await call("GET", "/sync/learning?cursor=0&limit=1", a.token))
    .body;
  assert.equal(delta.changes[0].record.id, attemptId);
  assert.equal(delta.changes[0].record.questions.length, 1);
  set = (
    await call("POST", `/sets/${sid}/generate`, a.token, {
      kind: "exam",
      count: 1,
      difficulty: "medium",
    })
  ).body.set;
  const exam = set.collections.find((d: any) => d.kind === "exam");
  const eq = set.questions.find((q: any) => q.collection_id === exam.id);
  assert.equal(
    (
      await call("POST", "/exams/start", b.token, {
        id: randomUUID(),
        setId: sid,
        collectionId: exam.id,
      })
    ).status,
    403,
  );
  const session = (
    await call("POST", "/exams/start", a.token, {
      id: randomUUID(),
      setId: sid,
      collectionId: exam.id,
    })
  ).body.session;
  assert.equal(
    (
      await call("POST", "/attempts", a.token, {
        id: randomUUID(),
        setId: sid,
        collectionId: exam.id,
        answers: { [eq.id]: 0 },
      })
    ).status,
    403,
  );
  advance(71000);
  const late = await call("POST", "/attempts", a.token, {
    id: randomUUID(),
    setId: sid,
    collectionId: exam.id,
    sessionId: session.id,
    answers: { [eq.id]: 0 },
  });
  assert.equal(late.body.attempt.score, 0);
  assert.equal(
    (await call("GET", "/exams/active", a.token)).body.sessions.length,
    0,
  );
  assert.equal((await call("GET", "/analytics/advanced", b.token)).status, 403);
  assert.equal(
    (await call("GET", "/analytics/advanced", a.token)).body.topics.length,
    1,
  );
});
test("one-time recovery revokes sessions, consumes codes and supports expiration", async (t) => {
  const { call, register, advance } = await setup(t);
  const a = await register();
  assert.equal(
    (await call("POST", "/me/recovery", a.token, { password: "wrong" })).status,
    401,
  );
  const recovery = (
    await call("POST", "/me/recovery", a.token, {
      password: "very-secure-password",
    })
  ).body;
  assert.equal(typeof recovery.code, "string");
  assert.equal(
    (
      await call("POST", "/auth/recover", undefined, {
        email: "student@example.com",
        code: recovery.code,
        password: "replacement-password",
      })
    ).status,
    200,
  );
  assert.equal((await call("GET", "/me", a.token)).status, 401);
  assert.equal(
    (
      await call("POST", "/auth/recover", undefined, {
        email: "student@example.com",
        code: recovery.code,
        password: "second-replacement",
      })
    ).status,
    401,
  );
  const login = (
    await call("POST", "/auth/login", undefined, {
      email: "student@example.com",
      password: "replacement-password",
    })
  ).body;
  const next = (
    await call("POST", "/me/recovery", login.token, {
      password: "replacement-password",
    })
  ).body;
  advance(366 * 86400000);
  assert.equal(
    (
      await call("POST", "/auth/recover", undefined, {
        email: "student@example.com",
        code: next.code,
        password: "replacement-again",
      })
    ).status,
    401,
  );
});
test("generation replay does not consume quota twice or duplicate a collection", async (t) => {
  const { call, register } = await setup(t);
  const a = await register();
  const sid = (
    await call("POST", "/sets", a.token, { title: "Replay-safe", notes: "ATP" })
  ).body.set.id;
  const operation = {
    id: randomUUID(),
    kind: "quiz",
    count: 1,
    difficulty: "medium",
  };
  const first = await call("POST", `/sets/${sid}/generate`, a.token, operation);
  assert.equal(first.status, 200);
  const replay = await call(
    "POST",
    `/sets/${sid}/generate`,
    a.token,
    operation,
  );
  assert.equal(replay.status, 200);
  assert.equal(replay.body.set.collections.length, 1);
  assert.equal(replay.body.plan.used, 1);
  assert.equal(
    (
      await call("POST", `/sets/${sid}/generate`, a.token, {
        ...operation,
        count: 2,
      })
    ).status,
    409,
