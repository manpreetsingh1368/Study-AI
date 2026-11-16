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
    "ATP transfers chemical energy.",
  );
  const sync = (await call("GET", "/sync?cursor=0", a.token)).body;
  assert.equal(sync.changes.at(-1).set.notebook.notes[0].id, note.id);
  const deletion = { id: randomUUID(), noteId: note.id };
  await call("POST", `/notebooks/${set.id}/delete-note`, a.token, deletion);
  await call("POST", `/notebooks/${set.id}/delete-note`, a.token, deletion);
  assert.equal(
    (await call("GET", "/sets", a.token)).body.sets[0].notebook.notes.length,
    0,
  );
  assert.equal(
    (await call("GET", `/notebooks/${set.id}/entries`, b.token)).status,
    404,
  );
  assert.equal(
    (
      await call(
        "GET",
        `/notebooks/${set.id}/entries?offset=0&limit=1`,
        a.token,
      )
    ).body.entries.length,
    1,
  );
});
test("notebook rejects fabricated quotations and releases failed quota without storing an answer", async (t) => {
  const { call, register } = await setup(t, (input) => ({
    ...supported(input),
    blocks: [
      {
        heading: "Unsupported",
        text: "A false answer",
        citations: [
          {
            chunkId: input.chunks[0].id,
            quote: "This sentence never appeared in the source.",
          },
        ],
      },
    ],
  }));
  const a = await register("a@example.com"),
    set = (
      await call("POST", "/sets", a.token, {
        title: "Lecture",
        notes: sourceText,
      })
    ).body.set;
  assert.equal(
    (
      await call("POST", `/notebooks/${set.id}/ask`, a.token, {
        id: randomUUID(),
        kind: "summary",
        prompt: "Overview",
        sourceIds: [set.id],
      })
    ).status,
    502,
  );
  assert.equal((await call("GET", "/me", a.token)).body.plan.used, 0);
  assert.equal(
    (await call("GET", "/sets", a.token)).body.sets[0].notebook.entries.length,
    0,
  );
});
test("source selection excludes previous conversations about unchecked sources; all modes share quota", async (t) => {
  const inputs: NotebookInput[] = [];
  const { call, register } = await setup(t, (input) => {
    inputs.push(input);
    return supported(input);
  });
  const a = await register("a@example.com");
  const one = (
      await call("POST", "/sets", a.token, { title: "One", notes: sourceText })
    ).body.set,
    two = (
      await call("POST", "/sets", a.token, { title: "Two", notes: sourceText })
    ).body.set;
  for (const [kind, sources] of [
    ["chat", [one.id]],
    ["guide", [two.id]],
    ["faq", [two.id]],
  ] as const) {
    assert.equal(
      (
        await call("POST", `/notebooks/${one.id}/ask`, a.token, {
          id: randomUUID(),
          kind,
          prompt: "Help me study",
          sourceIds: sources,
        })
      ).status,
      200,
    );
  }
  assert.equal(inputs[1].history.length, 0);
  assert.equal(
    inputs[1].chunks.every((c) => c.setId === two.id),
    true,
  );
  assert.equal(
    (
      await call("POST", `/notebooks/${one.id}/ask`, a.token, {
        id: randomUUID(),
        kind: "summary",
        prompt: "Overview",
        sourceIds: [one.id],
      })
    ).status,
    429,
  );
});
test("citation normalization and explicit insufficient-evidence behavior", () => {
  const chunks = splitSource(
    { setId: "s", sourceId: "s:notes", title: "Notes", version: 1, page: null },
    "ATP transfers\n chemical energy.",
  );
  assert.equal(
    validatedEvidence(
      supported({ kind: "chat", prompt: "", history: [], chunks }),
      chunks,
    ).blocks.length,
    1,
  );
  assert.throws(() =>
    validatedEvidence(
      {
        ...supported({ kind: "chat", prompt: "", history: [], chunks }),
        blocks: [
          {
            heading: "Bad",
            text: "Bad",
            citations: [
              { chunkId: "invented", quote: "ATP transfers chemical energy." },
            ],
          },
        ],
      },
      chunks,
    ),
  );
  assert.equal(
    validatedEvidence(
      { insufficientEvidence: true, blocks: [], followUps: [] },
      chunks,
    ).insufficientEvidence,
    true,
  );
  assert.throws(() =>
    validatedEvidence(
      { insufficientEvidence: false, blocks: [], followUps: [] },
      chunks,
    ),
  );
});
test("PDF grounding carries a verified page reference and permits PDF-only sources", async (t) => {
  const { PDFDocument } = await import("pdf-lib");
  const pdf = await PDFDocument.create();
  pdf.addPage().drawText("Introduction to cell biology.");
  pdf.addPage().drawText("ATP transfers chemical energy.");
  const bytes = Buffer.from(await pdf.save());
  // Use the real multipart route rather than injecting extracted text.
  const directory = mkdtempSync(join(tmpdir(), "pdf-grounding-"));
  const app = createApp({
    dataDir: directory,
    uploadDir: join(directory, "uploads"),
    notebookGenerate: async (input) => ({
      insufficientEvidence: false,
      blocks: [
        {
          heading: "From the PDF",
          text: "ATP is an energy carrier.",
          citations: [
            {
              chunkId: input.chunks.find((c) => c.page === 2)!.id,
              quote: "ATP transfers chemical energy.",
            },
          ],
        },
      ],
      followUps: [],
    }),
  });
  await app.ready();
  t.after(async () => {
    await app.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const auth = (
    await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        name: "PDF Reader",
        email: "reader@example.com",
        password: "pdf-reader-password",
      },
    })
  ).json();
  const set = (
    await app.inject({
      method: "POST",
      url: "/sets",
      headers: { authorization: `Bearer ${auth.token}` },
      payload: { title: "PDF only", notes: "" },
    })
  ).json().set;
  const boundary = "grounded-pdf";
  const upload = await app.inject({
