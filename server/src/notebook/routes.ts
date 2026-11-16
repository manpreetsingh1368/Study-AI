import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { createHash } from "node:crypto";
import { join } from "node:path";
import {
  notebookGenerate,
  pdfPages,
  splitSource,
  validatedEvidence,
  type NotebookInput,
  type NotebookOutput,
  type SourceChunk,
} from "./grounding.js";
export function registerNotebookRoutes(
  app: FastifyInstance,
  c: any,
  generate: (
    input: NotebookInput,
  ) => Promise<NotebookOutput> = notebookGenerate,
) {
  const { db, user, owned, get, all, run, plan, change, now, fail, uploads } =
    c;
  const digest = (input: unknown) =>
    createHash("sha256").update(JSON.stringify(input)).digest("hex");
  const entry = (r: any) => ({
    ...r,
    sourceIds: JSON.parse(r.source_ids),
    content: JSON.parse(r.content),
  });
  app.get("/notebooks/:id/entries", async (req) => {
    const u = user(req),
      sid = (req.params as any).id;
    owned(u.id, sid);
    const q = z
      .object({
        offset: z.coerce.number().int().min(0).default(0),
        limit: z.coerce.number().int().min(1).max(100).default(30),
      })
      .parse(req.query);
    return {
      entries: all(
        "SELECT * FROM notebook_entries WHERE notebook_id=? ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?",
        sid,
        q.limit,
        q.offset,
      ).map(entry),
    };
