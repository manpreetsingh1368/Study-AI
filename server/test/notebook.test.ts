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
