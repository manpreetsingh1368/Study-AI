import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createApp } from "../src/app.js";
import {
  splitSource,
  validatedEvidence,
  type NotebookInput,
  type NotebookOutput,
} from "../src/notebook/grounding.js";
const sourceText =
  "ATP transfers chemical energy. Cells use ATP to drive many cellular processes.";
const supported = (input: NotebookInput): NotebookOutput => ({
  insufficientEvidence: false,
  blocks: [
    {
      heading: "Key concept",
      text: "ATP transfers energy for cellular processes.",
      citations: [
        {
          chunkId: input.chunks[0].id,
          quote: "ATP transfers chemical energy.",
        },
      ],
    },
  ],
  followUps: ["How do cells use this energy?"],
});
async function setup(t: any, generate = supported) {
  const dir = mkdtempSync(join(tmpdir(), "notebook-"));
  const app = createApp({
    dataDir: dir,
    uploadDir: join(dir, "uploads"),
    notebookGenerate: async (i) => generate(i),
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
  async function register(email: string) {
    return (
      await call("POST", "/auth/register", undefined, {
        name: "Student",
        email,
        password: "notebook-test-password",
      })
    ).body;
  }
  return { call, register };
}
test("notebook: verified citations, idempotent quota, pinned notes, source ownership and sync", async (t) => {
  const { call, register } = await setup(t);
  const a = await register("a@example.com"),
    b = await register("b@example.com");
  const set = (
    await call("POST", "/sets", a.token, {
      title: "Cell biology",
      notes: sourceText,
    })
  ).body.set;
  const other = (
    await call("POST", "/sets", b.token, {
      title: "Private notes",
      notes: sourceText,
    })
  ).body.set;
  const request = {
    id: randomUUID(),
    kind: "chat",
    prompt: "Explain ATP.",
    sourceIds: [set.id],
  };
  assert.equal(
    (await call("POST", `/notebooks/${set.id}/ask`, b.token, request)).status,
    404,
  );
  assert.equal(
    (
      await call("POST", `/notebooks/${set.id}/ask`, a.token, {
        ...request,
        sourceIds: [other.id],
      })
    ).status,
    404,
  );
  const answer = await call(
    "POST",
    `/notebooks/${set.id}/ask`,
    a.token,
    request,
  );
  assert.equal(answer.status, 200);
  assert.equal(answer.body.entry.content.blocks[0].citations[0].setId, set.id);
  assert.equal(
    answer.body.entry.content.blocks[0].citations[0].quote,
    "ATP transfers chemical energy.",
  );
  assert.equal(
    (await call("POST", `/notebooks/${set.id}/ask`, a.token, request)).body.plan
      .used,
    1,
  );
  assert.equal(
    (
      await call("POST", `/notebooks/${set.id}/ask`, a.token, {
        ...request,
        prompt: "Changed question",
      })
    ).status,
    409,
  );
  const note = {
    id: randomUUID(),
    title: "Remember this",
    text: "ATP transfers energy.",
    entryId: request.id,
  };
  assert.equal(
    (await call("POST", `/notebooks/${set.id}/notes`, a.token, note)).status,
    200,
  );
  assert.equal(
    (await call("POST", `/notebooks/${set.id}/notes`, a.token, note)).status,
    200,
  );
  const library = (await call("GET", "/sets", a.token)).body.sets[0];
  assert.equal(library.notebook.entries.length, 1);
  assert.equal(library.notebook.notes.length, 1);
  assert.equal(
    library.notebook.notes[0].citations[0].quote,
