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
  });
  app.post("/notebooks/:id/notes", async (req) => {
    const u = user(req),
      sid = (req.params as any).id,
      b = z
        .object({
          id: z.uuid(),
          title: z.string().trim().min(1).max(150),
          text: z.string().trim().min(1).max(30000),
          entryId: z.uuid().optional(),
        })
        .parse(req.body);
    owned(u.id, sid);
    return db.transaction(() => {
      const existing = get("SELECT * FROM notebook_notes WHERE id=?", b.id);
      if (existing) {
        if (
          existing.notebook_id !== sid ||
          existing.title !== b.title ||
          existing.text !== b.text
        )
          fail(409, "Note identifier already used.");
        return { ok: true, notebook: notebookState(sid, get, all) };
      }
      if (
        get(
          "SELECT count(*) n FROM notebook_notes WHERE notebook_id=? AND deleted=0",
          sid,
        ).n >= 100
      )
      let citations: object[] = [];
      if (b.entryId) {
        const original = get(
          "SELECT * FROM notebook_entries WHERE id=? AND notebook_id=?",
          b.entryId,
          sid,
        );
        if (!original) fail(404, "Original answer not found.");
        citations = JSON.parse(original.content).blocks.flatMap(
          (block: any) => block.citations,
        );
      }
      run(
        "INSERT INTO notebook_notes VALUES(?,?,?,?,?,?,0)",
        b.id,
        sid,
        b.title,
        b.text,
        JSON.stringify(citations),
        now(),
      );
      change(sid, u.id);
      return { ok: true, notebook: notebookState(sid, get, all) };
    })();
  });
  app.post("/notebooks/:id/delete-note", async (req) => {
    const u = user(req),
      sid = (req.params as any).id,
      b = z.object({ id: z.uuid(), noteId: z.uuid() }).parse(req.body);
    owned(u.id, sid);
    db.transaction(() => {
      const note = get(
        "SELECT * FROM notebook_notes WHERE id=? AND notebook_id=?",
        b.noteId,
        sid,
      );
      if (!note) fail(404, "Note not found.");
      if (!note.deleted) {
        run("UPDATE notebook_notes SET deleted=1 WHERE id=?", b.noteId);
        change(sid, u.id);
      }
    })();
    return { ok: true, notebook: notebookState(sid, get, all) };
  });
  app.delete("/notebooks/:id/notes/:noteId", async (req) => {
    const u = user(req),
      { id: sid, noteId } = req.params as any;
    owned(u.id, sid);
    db.transaction(() => {
      run(
        "UPDATE notebook_notes SET deleted=1 WHERE id=? AND notebook_id=?",
        noteId,
        sid,
      );
      change(sid, u.id);
    })();
    return { ok: true };
  });
  app.post("/notebooks/:id/ask", async (req) => {
    const u = user(req),
      sid = (req.params as any).id;
    const b = z
      .object({
        id: z.uuid(),
        kind: z.enum(["chat", "summary", "guide", "faq"]),
        prompt: z.string().trim().min(1).max(3000),
        sourceIds: z.array(z.uuid()).min(1).max(50),
      })
      .parse(req.body);
    owned(u.id, sid);
    const sourceIds = [...new Set(b.sourceIds)].sort();
    const hash = digest({ sid, kind: b.kind, prompt: b.prompt, sourceIds });
    const previous = get("SELECT * FROM notebook_entries WHERE id=?", b.id);
    if (previous) {
      if (previous.notebook_id !== sid || previous.request_hash !== hash)
        fail(409, "Request identifier reused with different data.");
      return { entry: entry(previous), plan: plan(u.id) };
    }
    const allowance = plan(u.id);
    if (allowance.used >= allowance.generations)
      fail(
        429,
        "Daily AI allowance reached. Chat and Studio use the same allowance as quiz generation.",
      );
    const sources = sourceIds.map((sourceId) => owned(u.id, sourceId));
    const selectedBytes = sourceIds.reduce(
      (total: number, id: string) =>
        total +
        (get("SELECT bytes FROM documents WHERE set_id=?", id)?.bytes || 0),
      0,
    );
    if (selectedBytes > 2147483648)
      fail(413, "Selected PDFs exceed the 2 GiB notebook allowance.");
    const chunks: SourceChunk[] = [];
    let total = 0;
    for (const source of sources) {
      if (source.notes.trim()) {
        total += source.notes.length;
        chunks.push(
          ...splitSource(
            {
              setId: source.id,
              sourceId: `${source.id}:notes`,
              title: `${source.title} · notes`,
              version: source.version,
              page: null,
            },
            source.notes,
          ),
        );
      }
      const document = get("SELECT * FROM documents WHERE set_id=?", source.id);
      if (document) {
        const pages = await pdfPages(join(uploads, document.id));
        for (let i = 0; i < pages.length; i++) {
          total += pages[i].length;
          chunks.push(
            ...splitSource(
              {
                setId: source.id,
                sourceId: document.id,
                title: document.filename,
                version: source.version,
                page: i + 1,
              },
              pages[i],
            ),
          );
        }
      }
      if (total > 100000)
        fail(
          413,
          "Selected sources exceed 100,000 characters of extracted text. Select fewer sources or a shorter document.",
        );
    }
    if (!chunks.length)
      fail(
        422,
        "No readable source text was found. Paste notes or use a PDF with selectable text.",
      );
    db.transaction(() => {
      owned(u.id, sid);
      for (const source of sources) {
        if (owned(u.id, source.id).version !== source.version)
          fail(409, "A source changed while loading. Refresh and try again.");
      }
      const previousUsage = get(
        "SELECT * FROM generation_usage WHERE id=?",
        b.id,
      );
      if (
        previousUsage &&
        (previousUsage.user_id !== u.id || previousUsage.request_hash !== hash)
      )
        fail(409, "Request identifier already used.");
      if (previousUsage?.status === "pending")
        fail(409, "This notebook request is still running. Refresh shortly.");
      const p = plan(u.id);
      if (p.used >= p.generations)
        fail(
          429,
          "Daily AI allowance reached. Chat and Studio use the same AI allowance as quiz generation.",
        );
      run(
        "INSERT INTO generation_usage(id,user_id,day,status,created_at,request_hash,request_config) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET day=excluded.day,status=excluded.status,created_at=excluded.created_at",
        b.id,
        u.id,
        new Date(now()).toISOString().slice(0, 10),
        "pending",
        now(),
        hash,
        hash,
      );
    })();
    try {
      const history = all(
        "SELECT prompt,content,source_ids FROM notebook_entries WHERE notebook_id=? AND kind='chat' ORDER BY created_at DESC,id DESC LIMIT 12",
        sid,
      )
        .filter((r: any) =>
          (JSON.parse(r.source_ids) as string[]).every((id) =>
            sourceIds.includes(id),
          ),
        )
        .slice(0, 4)
        .reverse()
        .map((r: any) => ({
          prompt: r.prompt,
          answer: JSON.parse(r.content)
            .blocks.map((block: any) => block.text)
            .join("\n"),
        }));
      const output = await generate({
        kind: b.kind,
        prompt: b.prompt,
        chunks,
        history,
      });
      const verified = validatedEvidence(output, chunks);
      db.transaction(() => {
        owned(u.id, sid);
        for (const source of sources) {
          if (owned(u.id, source.id).version !== source.version)
            fail(
              409,
              "A source changed during generation. The response was not saved. Please retry.",
            );
        }
        run(
          "INSERT INTO notebook_entries VALUES(?,?,?,?,?,?,?,?)",
          b.id,
          sid,
          b.kind,
          b.prompt,
          JSON.stringify(sourceIds),
          hash,
          JSON.stringify(verified),
          now(),
        );
        run("UPDATE generation_usage SET status='success' WHERE id=?", b.id);
        run(
          "INSERT INTO notebook_preferences VALUES(?,?) ON CONFLICT(notebook_id) DO UPDATE SET source_ids=excluded.source_ids",
          sid,
          JSON.stringify(sourceIds),
        );
        change(sid, u.id);
      })();
      return {
        entry: entry(get("SELECT * FROM notebook_entries WHERE id=?", b.id)),
        plan: plan(u.id),
      };
    } catch (e) {
      run("UPDATE generation_usage SET status='failed' WHERE id=?", b.id);
      throw e;
    }
  });
}
export function notebookState(sid: string, get: any, all: any) {
  return {
    entries: all(
      "SELECT * FROM notebook_entries WHERE notebook_id=? ORDER BY created_at DESC,id DESC LIMIT 80",
      sid,
    ).map((r: any) => ({
      ...r,
      sourceIds: JSON.parse(r.source_ids),
      content: JSON.parse(r.content),
    })),
    total: get(
      "SELECT count(*) n FROM notebook_entries WHERE notebook_id=?",
      sid,
    ).n,
    notes: all(
      "SELECT * FROM notebook_notes WHERE notebook_id=? AND deleted=0 ORDER BY created_at DESC",
      sid,
    ).map((n: any) => ({ ...n, citations: JSON.parse(n.citations) })),
    sourceIds: JSON.parse(
      get(
        "SELECT source_ids FROM notebook_preferences WHERE notebook_id=?",
        sid,
      )?.source_ids || JSON.stringify([sid]),
    ),
  };
}
