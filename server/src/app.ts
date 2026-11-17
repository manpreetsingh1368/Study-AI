import Fastify from "fastify";
import { registerNotebookRoutes, notebookState } from "./notebook/routes.js";
import type { NotebookInput, NotebookOutput } from "./notebook/grounding.js";
import rateLimit from "@fastify/rate-limit";
import multipart from "@fastify/multipart";
import helmet from "@fastify/helmet";
import { hash, verify, argon2id } from "argon2";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
  unlinkSync,
  existsSync,
  renameSync,
} from "node:fs";
import { join } from "node:path";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { openDatabase } from "./database/db.js";
import { validatePdf } from "./ai/pdf.js";
import { users } from "./database/schema.js";
import { registerLearningRoutes } from "./routes/learning.js";
import {
  generate,
  difficulty,
  type GenerationInput,
  type Generated,
} from "./ai/gemini.js";
const id = () => randomUUID();
const digest = (s: string) => createHash("sha256").update(s).digest("hex");
const fail = (statusCode: number, message: string): never => {
  throw Object.assign(new Error(message), { statusCode });
};
const account = z.object({
  email: z
    .email()
    .max(254)
    .transform((s) => s.toLowerCase()),
  password: z.string().min(12).max(128),
  name: z.string().trim().min(1).max(100),
});
const credentials = account.pick({ email: true, password: true });
const setInput = z.object({
  title: z.string().trim().min(1).max(200),
  notes: z.string().max(100000),
  folder: z.string().trim().max(80).default(""),
});
export function createApp(
  options: {
    dataDir?: string;
    uploadDir?: string;
    generate?: (i: GenerationInput) => Promise<Generated>;
    now?: () => number;
    notebookGenerate?: (input: NotebookInput) => Promise<NotebookOutput>;
  } = {},
) {
  const { sqlite: db, orm } = openDatabase(
    options.dataDir || process.env.DATA_DIR || "./data",
  );
  const uploads = options.uploadDir || process.env.UPLOAD_DIR || "./uploads";
  mkdirSync(uploads, { recursive: true, mode: 0o700 });
  const now = options.now || Date.now;
  const app = Fastify({
    logger: false,
    bodyLimit: 150000,
    trustProxy: ["127.0.0.1", "::1"],
  });
  app.register(helmet);
  app.register(rateLimit, { max: 120, timeWindow: 60000 });
  app.register(multipart, {
    limits: {
      fileSize: Number(process.env.MAX_PDF_BYTES || 10485760),
      files: 1,
      fields: 0,
      parts: 1,
    },
  });
  const get = (sql: string, ...args: any[]): any =>
    db.prepare(sql).get(...args);
  const all = (sql: string, ...args: any[]): any[] =>
    db.prepare(sql).all(...args);
  const run = (sql: string, ...args: any[]) => db.prepare(sql).run(...args);
  function user(req: any) {
    const token = req.headers.authorization?.match(/^Bearer (\S+)$/)?.[1];
    if (!token) return fail(401, "Sign in to continue.");
    const u = get(
      "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>?",
      digest(token),
      now(),
    );
    if (!u) return fail(401, "Your session has expired. Sign in again.");
    return u;
  }
  const publicUser = (u: any) => ({
    id: u.id,
    email: u.email,
    name: u.name,
    role: u.role,
  });
  function admin(req: any) {
    const u = user(req);
    if (u.role !== "admin") fail(403, "Administrator access required.");
    return u;
  }
  function owned(uid: string, sid: string) {
    const s = get(
      "SELECT * FROM study_sets WHERE id=? AND user_id=? AND deleted=0",
      sid,
      uid,
    );
    if (!s) fail(404, "Study set not found.");
    return s;
  }
  function change(sid: string, uid: string) {
    const s = get("SELECT * FROM study_sets WHERE id=?", sid);
    run(
      "INSERT INTO sync_changes(user_id,set_id,version,deleted) VALUES(?,?,?,?)",
      uid,
      sid,
      s.version,
      s.deleted,
    );
  }
  function full(s: any) {
    return {
      ...s,
      notebook: notebookState(s.id, get, all),
      collections: all(
        "SELECT * FROM collections WHERE set_id=? ORDER BY created_at DESC",
        s.id,
      ),
      questions: all(
        "SELECT * FROM questions WHERE set_id=? ORDER BY position",
        s.id,
      ).map((q) => ({ ...q, choices: JSON.parse(q.choices) })),
      flashcards: all("SELECT * FROM flashcards WHERE set_id=?", s.id),
      document:
        get("SELECT id,filename,bytes FROM documents WHERE set_id=?", s.id) ||
        null,
    };
  }
  function plan(uid: string) {
    const sub = get(
      "SELECT * FROM subscriptions WHERE user_id=? AND starts_at<=? AND expires_at>?",
      uid,
      now(),
      now(),
    );
    const pro = !!sub,
      prefix = pro ? "PRO" : "FREE";
    const day = new Date(now()).toISOString().slice(0, 10);
    return {
      name: pro ? "Pro" : "Free",
      pro,
      expiresAt: sub?.expires_at || null,
      generations: Number(
        process.env[`${prefix}_GENERATIONS`] || (pro ? 30 : 3),
      ),
      sets: Number(process.env[`${prefix}_SETS`] || (pro ? 200 : 5)),
      cards: Number(process.env[`${prefix}_CARDS`] || (pro ? 50 : 5)),
      used: get(
        "SELECT count(*) n FROM generation_usage WHERE user_id=? AND day=? AND status IN ('pending','success')",
        uid,
        day,
      ).n,
    };
  }
  function newSet(
    uid: string,
    title: string,
    notes: string,
    sid = id(),
    folder = "",
  ) {
    if (
      get(
        "SELECT count(*) n FROM study_sets WHERE user_id=? AND deleted=0",
        uid,
      ).n >= plan(uid).sets
    )
      fail(403, "Your saved study set limit has been reached.");
    run(
      "INSERT INTO study_sets(id,user_id,title,notes,version,deleted,created_at,updated_at,folder) VALUES(?,?,?,?,1,0,?,?,?)",
      sid,
      uid,
      title,
      notes,
      now(),
      now(),
      folder,
    );
    change(sid, uid);
    return sid;
  }
  const session = (u: any) => {
    const token = randomBytes(32).toString("base64url");
    run(
      "INSERT INTO sessions VALUES(?,?,?)",
      digest(token),
      u.id,
      now() + Number(process.env.SESSION_DAYS || 30) * 86400000,
    );
    return { token, user: publicUser(u) };
  };
  app.setErrorHandler((error: any, _req, reply) => {
    if (error instanceof z.ZodError)
      return reply.code(400).send({
        message: "Invalid input.",
        issues: error.issues.map((x) => ({
          path: x.path,
          message: x.message,
        })),
      });
    const status = error.statusCode || 500;
    if (status >= 500)
      run(
        "INSERT INTO application_errors VALUES(?,?,?)",
        id(),
        error.code || "INTERNAL",
        now(),
      );
    reply.code(status).send({
      message:
        status >= 500 && status !== 503
          ? "The request could not be completed. Please retry."
          : error.message,
    });
  });
  app.get("/plans", async () => ({
    free: {
      generations: Number(process.env.FREE_GENERATIONS || 3),
      cards: Number(process.env.FREE_CARDS || 5),
      sets: Number(process.env.FREE_SETS || 5),
    },
    pro: {
      generations: Number(process.env.PRO_GENERATIONS || 30),
      cards: Number(process.env.PRO_CARDS || 50),
      sets: Number(process.env.PRO_SETS || 200),
    },
  }));
  app.get("/health", async () => ({ status: "ok" }));
  app.post(
    "/auth/register",
    { config: { rateLimit: { max: 5, timeWindow: 60000 } } },
    async (req, reply) => {
      const b = account.parse(req.body);
      const passwordHash = await hash(b.password, { type: argon2id });
      try {
        const u = {
          id: id(),
          email: b.email,
          name: b.name,
          passwordHash,
          role: "student",
          createdAt: now(),
        };
        orm.insert(users).values(u).run();
        reply.code(201);
        return session(u);
      } catch (e: any) {
        if (e.code?.includes("SQLITE_CONSTRAINT"))
          fail(409, "Account could not be registered with that email.");
        throw e;
      }
    },
  );
  app.post(
    "/auth/login",
    { config: { rateLimit: { max: 8, timeWindow: 60000 } } },
    async (req) => {
      const b = credentials.parse(req.body);
      const u = orm.select().from(users).where(eq(users.email, b.email)).get();
      // Always perform an expensive hash operation for unknown accounts.
      if (!u) {
        await hash(b.password, { type: argon2id });
        return fail(401, "Email or password is incorrect.");
      }
      if (!(await verify(u.passwordHash, b.password)))
        fail(401, "Email or password is incorrect.");
      return session(u);
    },
  );
  app.post("/auth/logout", async (req) => {
    user(req);
    run(
      "DELETE FROM sessions WHERE token_hash=?",
      digest(req.headers.authorization!.slice(7)),
    );
    return { ok: true };
  });
  app.post("/me/recovery", async (req) => {
    const u = user(req),
      b = z.object({ password: z.string().max(128) }).parse(req.body);
    if (!(await verify(u.password_hash, b.password)))
      fail(401, "Password is incorrect.");
    const code = randomBytes(32).toString("base64url"),
      expiresAt = now() + 365 * 86400000;
    run(
      "INSERT INTO recovery_codes VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET code_hash=excluded.code_hash,expires_at=excluded.expires_at,created_at=excluded.created_at",
      u.id,
      digest(code),
      expiresAt,
      now(),
    );
    return { code, expiresAt };
  });
  app.post(
    "/auth/recover",
    { config: { rateLimit: { max: 5, timeWindow: 60000 } } },
    async (req) => {
      const b = z
        .object({
          email: z
            .email()
            .max(254)
            .transform((s) => s.toLowerCase()),
          code: z.string().min(30).max(100),
          password: z.string().min(12).max(128),
        })
        .parse(req.body);
      const passwordHash = await hash(b.password, { type: argon2id });
      db.transaction(() => {
        const recovery = get(
          "SELECT r.user_id FROM recovery_codes r JOIN users u ON u.id=r.user_id WHERE u.email=? AND r.code_hash=? AND r.expires_at>?",
          b.email,
          digest(b.code),
          now(),
        );
        if (!recovery)
          fail(401, "Email or recovery code is invalid or expired.");
        run(
          "UPDATE users SET password_hash=? WHERE id=?",
          passwordHash,
          recovery.user_id,
        );
        run("DELETE FROM recovery_codes WHERE user_id=?", recovery.user_id);
        run("DELETE FROM sessions WHERE user_id=?", recovery.user_id);
      })();
      return { ok: true };
    },
  );
  app.get("/me", async (req) => {
    const u = user(req);
    return { user: publicUser(u), plan: plan(u.id) };
  });
  app.patch("/me", async (req) => {
    const u = user(req),
      b = z.object({ name: z.string().trim().min(1).max(100) }).parse(req.body);
    run("UPDATE users SET name=? WHERE id=?", b.name, u.id);
    return { user: publicUser({ ...u, name: b.name }) };
  });
  app.post("/me/password", async (req) => {
    const u = user(req),
      b = z
        .object({
          current: z.string().max(128),
          password: z.string().min(12).max(128),
        })
        .parse(req.body);
    if (!(await verify(u.password_hash, b.current)))
      fail(401, "Current password is incorrect.");
    const h = await hash(b.password, { type: argon2id });
    db.transaction(() => {
      run("UPDATE users SET password_hash=? WHERE id=?", h, u.id);
      run("DELETE FROM sessions WHERE user_id=?", u.id);
      run("DELETE FROM recovery_codes WHERE user_id=?", u.id);
    })();
    return { ok: true };
  });
  app.delete("/me", async (req) => {
    const u = user(req),
      b = z
        .object({
          password: z.string().max(128).optional(),
    const docs = all(
      "SELECT d.id FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE s.user_id=?",
      u.id,
    );
    run("DELETE FROM users WHERE id=?", u.id);
    for (const d of docs)
      if (existsSync(join(uploads, d.id))) unlinkSync(join(uploads, d.id));
    return { ok: true };
  });
  app.get("/sets", async (req) => {
    const u = user(req);
    return {
      sets: all(
        "SELECT * FROM study_sets WHERE user_id=? AND deleted=0 AND (parent_notebook_id IS NULL OR EXISTS(SELECT 1 FROM study_sets p WHERE p.id=study_sets.parent_notebook_id AND p.deleted=0)) ORDER BY updated_at DESC",
        u.id,
      ).map(full),
    };
  });
  app.post("/sets", async (req, reply) => {
    const u = user(req),
      b = setInput.parse(req.body);
    const sid = db.transaction(() =>
      newSet(
        u.id,
        b.title,
        b.notes,
        undefined,
        b.folder,
        b.parentNotebookId || null,
      ),
    )();
    reply.code(201);
    return { set: full(owned(u.id, sid)) };
  });
  app.patch("/sets/:id", async (req) => {
    const u = user(req),
      sid = (req.params as any).id,
      b = setInput
        .extend({ version: z.number().int().positive() })
        .parse(req.body);
    return db.transaction(() => {
      const s = owned(u.id, sid);
      if (s.version !== b.version)
        fail(
          409,
          "This set changed on another device. Refresh before editing.",
        );
      run(
        "UPDATE study_sets SET title=?,notes=?,folder=?,version=version+1,updated_at=? WHERE id=?",
        b.title,
        b.notes,
        b.folder,
        now(),
        sid,
      );
      change(sid, u.id);
      return { set: full(owned(u.id, sid)) };
    })();
  });
  app.delete("/sets/:id", async (req) => {
    const u = user(req),
      sid = (req.params as any).id,
      b = z.object({ version: z.number().int().positive() }).parse(req.body);
    db.transaction(() => {
      const s = owned(u.id, sid);
      if (s.version !== b.version)
        fail(409, "This set changed. Refresh before deleting.");
      softDelete(sid, u.id);
    })();
    return { ok: true };
  });
  app.post("/sets/:id/pdf", async (req) => {
    const u = user(req),
      s = owned(u.id, (req.params as any).id);
    const previousDocument = get(
      "SELECT * FROM documents WHERE set_id=?",
      s.id,
    );
    const did = z.uuid().parse(req.headers["x-document-id"] || id());
    if (previousDocument?.id === did) return { set: full(s) };
    if (previousDocument && Number(req.headers["x-set-version"]) !== s.version)
      fail(409, "Refresh the study set before replacing its PDF.");
    const part = await req.file();
    if (!part || part.mimetype !== "application/pdf")
      fail(400, "Select a PDF document.");
    if (get("SELECT id FROM documents WHERE id=?", did))
      fail(409, "Document identifier already used.");
    const temporary = join(uploads, `${id()}.pending`);
    let promoted = false,
      byteCount = 0,
      signature = Buffer.alloc(0);
    try {
      await pipeline(
        part!.file,
        new Transform({
          transform(chunk, _encoding, callback) {
            byteCount += chunk.length;
            if (signature.length < 5)
              signature = Buffer.concat([
                signature,
                chunk.subarray(0, 5 - signature.length),
              ]);
            callback(null, chunk);
          },
        }),
        createWriteStream(temporary, { mode: 0o600, flags: "wx" }),
      );
      if (part!.file.truncated)
        fail(413, "PDF exceeds the per-file upload limit.");
      if (signature.toString() !== "%PDF-") fail(400, "Invalid PDF signature.");
      await validatePdf(temporary);
      db.transaction(() => {
        const current = owned(u.id, s.id);
        if (current.version !== s.version)
          fail(
            409,
            "This material changed during upload. Refresh and try again.",
          );
        if (get("SELECT id FROM documents WHERE id=?", did))
          fail(409, "Document identifier already used.");
        if (
          get(
            "SELECT coalesce(sum(d.bytes),0) n FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE s.user_id=?",
            u.id,
          ).n -
            (previousDocument?.bytes || 0) +
            byteCount >
          Number(process.env.MAX_STORAGE_BYTES || 21474836480)
        )
          fail(403, "Storage limit reached.");
        const currentCapacity = capacity(current, get);
        if (
          currentCapacity.pdfBytes -
            (previousDocument?.bytes || 0) +
            byteCount >
          NOTEBOOK_PDF_BYTES
        )
          fail(403, "This notebook has reached its 2 GiB PDF allowance.");
        run(
          "INSERT INTO documents VALUES(?,?,?,?) ON CONFLICT(set_id) DO UPDATE SET id=excluded.id,filename=excluded.filename,bytes=excluded.bytes",
          did,
          s.id,
          part!.filename.slice(0, 200),
          byteCount,
        );
        run(
          "UPDATE study_sets SET version=version+1,updated_at=? WHERE id=?",
          now(),
          s.id,
        );
        change(s.id, u.id);
        if (current.parent_notebook_id)
          change(current.parent_notebook_id, u.id);
        renameSync(temporary, join(uploads, did));
        promoted = true;
      })();
    } catch (e) {
      if (existsSync(temporary)) unlinkSync(temporary);
      if (promoted && existsSync(join(uploads, did)))
        unlinkSync(join(uploads, did));
      throw e;
    }
    if (previousDocument && existsSync(join(uploads, previousDocument.id)))
      unlinkSync(join(uploads, previousDocument.id));
    return { set: full(owned(u.id, s.id)) };
  });
  app.get("/documents/:id", async (req, reply) => {
    const u = user(req),
      d = get(
        "SELECT d.* FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE d.id=? AND s.user_id=? AND s.deleted=0",
        (req.params as any).id,
        u.id,
      );
    if (!d) fail(404, "Document not found.");
    return reply
      .header("Cache-Control", "no-store")
      .header("Content-Disposition", 'attachment; filename="document.pdf"')
      .type("application/pdf")
      .send(createReadStream(join(uploads, d.id)));
  });
  app.post("/sets/:id/generate", async (req) => {
    const u = user(req),
      sid = (req.params as any).id,
      s = owned(u.id, sid),
      b = z
        .object({
          id: z.uuid().optional(),
          kind: z.enum(["quiz", "flashcards", "exam"]),
          count: z.number().int().min(1).max(50),
          difficulty,
        })
        .parse(req.body),
      p = plan(u.id);
    if ((b.kind === "exam" || b.difficulty === "hard") && !p.pro)
      fail(403, "This option requires Pro access.");
    if (b.kind === "flashcards" && b.count > p.cards)
      fail(403, `Your plan allows ${p.cards} flashcards per generation.`);
    if (b.kind !== "flashcards" && b.count > (p.pro ? 50 : 10))
      fail(403, "Question count exceeds your plan.");
    const doc = get("SELECT * FROM documents WHERE set_id=?", sid);
    if (!s.notes.trim() && !doc) fail(400, "Add notes or a PDF first.");
    const usage = b.id || id();
    const requestConfig = digest(
      JSON.stringify({
        sid,
        kind: b.kind,
        count: b.count,
        difficulty: b.difficulty,
      }),
    );
    const requestHash = digest(
      JSON.stringify({
        sid,
        version: s.version,
        kind: b.kind,
        count: b.count,
        difficulty: b.difficulty,
      }),
    );
    const previousUsage = get(
      "SELECT * FROM generation_usage WHERE id=?",
      usage,
    );
    if (previousUsage) {
      if (previousUsage.user_id !== u.id)
        fail(409, "Generation identifier already used.");
      // A successful retry returns its saved collection even though generation
      // itself incremented the source version.
      if (previousUsage.request_config !== requestConfig)
        fail(409, "Generation identifier reused with different options.");
      if (previousUsage.status === "success" && previousUsage.collection_id) {
        const collection = get(
          "SELECT * FROM collections WHERE id=? AND set_id=?",
          previousUsage.collection_id,
          sid,
        );
        if (!collection)
          fail(409, "Generation identifier belongs to another study set.");
        return { set: full(s), plan: plan(u.id), collectionId: collection.id };
      }
      if (previousUsage.request_hash !== requestHash)
        fail(409, "Generation identifier reused with different material.");
      if (previousUsage.status === "pending")
        fail(
          409,
          "This generation is still in progress. Refresh the study set shortly.",
        );
    }
    db.transaction(() => {
      const current = plan(u.id);
      if (current.used >= current.generations)
        fail(429, "Daily AI generation limit reached.");
      run(
        "INSERT INTO generation_usage(id,user_id,day,status,created_at,request_hash,request_config) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET day=excluded.day,status=excluded.status,created_at=excluded.created_at",
        usage,
        u.id,
        new Date(now()).toISOString().slice(0, 10),
        "pending",
        now(),
        requestHash,
        requestConfig,
      );
    })();
    try {
      let notes = s.notes,
        pdf: Buffer | undefined;
      if (doc) {
        if (doc.bytes <= 15728640) pdf = readFileSync(join(uploads, doc.id));
        else {
          const { pdfPages } = await import("./notebook/grounding.js");
          const extracted = (await pdfPages(join(uploads, doc.id))).join("\n");
          if (extracted.length + notes.length > 100000)
            fail(
              413,
              "This large PDF is saved, but its extracted text is too long for one generation. Paste the section you want to study into a separate source.",
            );
          notes += "\n" + extracted;
        }
      }
      const output = await (options.generate || generate)({ ...b, notes, pdf });
      db.transaction(() => {
        const current = owned(u.id, sid);
        if (current.version !== s.version)
          fail(409, "Material changed during generation. Try again.");
        const collectionId = id();
        run(
          "INSERT INTO collections VALUES(?,?,?,?,?)",
          collectionId,
          sid,
          b.kind,
          `${b.kind === "flashcards" ? "Flashcards" : b.kind === "exam" ? "Practice exam" : "Quiz"} · ${b.difficulty}`,
          now(),
        );
        if (b.kind === "flashcards") {
          for (const c of output.flashcards)
            run(
              "INSERT INTO flashcards(id,set_id,front,back,topic,difficulty,collection_id) VALUES(?,?,?,?,?,?,?)",
              id(),
              sid,
              c.front,
              c.back,
              c.topic,
              c.difficulty,
              collectionId,
            );
        } else {
          output.questions.forEach((q, i) =>
            run(
              "INSERT INTO questions(id,set_id,position,question,choices,answer,explanation,difficulty,topic,collection_id) VALUES(?,?,?,?,?,?,?,?,?,?)",
              id(),
              sid,
              i,
              q.question,
              JSON.stringify(q.choices),
              q.answer,
              q.explanation,
              q.difficulty,
              q.topic,
              collectionId,
            ),
          );
        }
        run(
          "UPDATE study_sets SET version=version+1,updated_at=? WHERE id=?",
          now(),
          sid,
        );
        change(sid, u.id);
        run(
          "UPDATE generation_usage SET status='success',collection_id=? WHERE id=?",
          collectionId,
          usage,
        );
      })();
      return { set: full(owned(u.id, sid)), plan: plan(u.id) };
    } catch (e) {
      run("UPDATE generation_usage SET status='failed' WHERE id=?", usage);
      throw e;
    }
  });
  app.post("/attempts", async (req) => {
    const u = user(req),
      b = z
        .object({
          id: z.uuid(),
          setId: z.uuid(),
          collectionId: z.string().max(80).optional(),
          sessionId: z.uuid().optional(),
          answers: z.record(z.string(), z.number().int().min(-1).max(3)),
        })
        .parse(req.body);
    const existing = get("SELECT * FROM quiz_attempts WHERE id=?", b.id);
    if (existing) {
      if (existing.user_id !== u.id) fail(409, "Operation ID already used.");
      return { attempt: existing };
    }
    owned(u.id, b.setId);
    let qs = b.collectionId
      ? all(
          "SELECT * FROM questions WHERE set_id=? AND collection_id=?",
          b.setId,
          b.collectionId,
        )
      : all("SELECT * FROM questions WHERE set_id=?", b.setId);
    let submittedAnswers = b.answers;
    let exam: any;
    if (b.sessionId) {
      exam = get(
        "SELECT * FROM quiz_sessions WHERE id=? AND user_id=? AND set_id=?",
        b.sessionId,
        u.id,
        b.setId,
      );
      if (!exam) fail(404, "Exam session not found.");
      if (exam.attempt_id) fail(409, "This exam was already submitted.");
      const questionIds = JSON.parse(exam.question_ids) as string[];
      qs = questionIds.map((qid) =>
        get("SELECT * FROM questions WHERE id=?", qid),
      );
      if (now() > exam.deadline + 10000) submittedAnswers = {};
    } else if (
      qs.some(
        (q) =>
          get("SELECT kind FROM collections WHERE id=?", q.collection_id)
            ?.kind === "exam",
      )
    )
      fail(403, "Start a timed exam session before submitting exam answers.");
    if (!qs.length) fail(400, "Generate questions first.");
    const score = qs.filter((q) => submittedAnswers[q.id] === q.answer).length;
    db.transaction(() => {
      run(
        "INSERT INTO quiz_attempts(id,user_id,set_id,score,total,created_at,collection_id) VALUES(?,?,?,?,?,?,?)",
        b.id,
        u.id,
        b.setId,
        score,
        qs.length,
        now(),
        exam?.collection_id || b.collectionId || null,
      );
      if (exam)
        run("UPDATE quiz_sessions SET attempt_id=? WHERE id=?", b.id, exam.id);
      for (const q of qs)
        run(
          "INSERT INTO quiz_answers VALUES(?,?,?)",
          b.id,
          q.id,
          submittedAnswers[q.id] ?? -1,
        );
    })();
    return { attempt: get("SELECT * FROM quiz_attempts WHERE id=?", b.id) };
  });
  app.post("/reviews", async (req) => {
    const u = user(req),
      b = z
        .object({ id: z.uuid(), cardId: z.uuid(), known: z.boolean() })
        .parse(req.body),
      existing = get("SELECT * FROM flashcard_reviews WHERE id=?", b.id);
    if (existing) {
      if (existing.user_id !== u.id) fail(409, "Operation ID already used.");
      return { review: existing };
    }
    const card = get("SELECT * FROM flashcards WHERE id=?", b.cardId);
    if (!card) fail(404, "Card not found.");
    owned(u.id, card.set_id);
    const previous = get(
      "SELECT * FROM flashcard_reviews WHERE user_id=? AND card_id=? ORDER BY reviewed_at DESC,rowid DESC LIMIT 1",
      u.id,
      b.cardId,
    );
    const days = b.known
      ? Math.min(180, previous?.known ? previous.interval_days * 2 : 1)
      : 1;
    run(
      "INSERT INTO flashcard_reviews VALUES(?,?,?,?,?,?,?)",
      b.id,
      u.id,
      b.cardId,
      b.known ? 1 : 0,
      now(),
      now() + days * 86400000,
      days,
    );
    return { review: get("SELECT * FROM flashcard_reviews WHERE id=?", b.id) };
  });
  app.get("/sync", async (req) => {
    const u = user(req),
      q = z
        .object({
          cursor: z.coerce.number().int().min(0).default(0),
          limit: z.coerce.number().int().min(1).max(100).default(50),
        })
        .parse(req.query);
    const changes = all(
      "SELECT * FROM sync_changes WHERE user_id=? AND seq>? ORDER BY seq LIMIT ?",
      u.id,
      q.cursor,
      q.limit,
    );
    return {
      changes: changes.map((c) => {
        const current = get("SELECT * FROM study_sets WHERE id=?", c.set_id);
        // Return the current snapshot for each sequence entry. Earlier pages
        // must not reintroduce a set that already has a later tombstone.
        return {
          ...c,
          version: current.version,
          deleted: current.deleted,
          set: current.deleted ? null : full(current),
        };
      }),
      cursor: changes.at(-1)?.seq ?? q.cursor,
      hasMore: changes.length === q.limit,
    };
  });
  app.get("/analytics", async (req) => {
    const u = user(req),
      attempts = all(
        "SELECT a.*,s.title FROM quiz_attempts a JOIN study_sets s ON s.id=a.set_id WHERE a.user_id=? ORDER BY a.created_at DESC",
        u.id,
      );
    return {
      sets: get(
        "SELECT count(*) n FROM study_sets WHERE user_id=? AND deleted=0 AND parent_notebook_id IS NULL",
        u.id,
      ).n,
      completed: attempts.length,
      average: attempts.length
        ? attempts.reduce((n, a) => n + (a.score / a.total) * 100, 0) /
          attempts.length
        : 0,
      reviewed: get(
        "SELECT count(*) n FROM flashcard_reviews WHERE user_id=?",
        u.id,
      ).n,
      attempts,
      daily: all(
        "SELECT day,sum(sessions) sessions,sum(cards) cards FROM (SELECT strftime('%Y-%m-%d',created_at/1000,'unixepoch') day,count(*) sessions,0 cards FROM quiz_attempts WHERE user_id=? GROUP BY day UNION ALL SELECT strftime('%Y-%m-%d',reviewed_at/1000,'unixepoch') day,0 sessions,count(*) cards FROM flashcard_reviews WHERE user_id=? GROUP BY day) GROUP BY day ORDER BY day DESC LIMIT 30",
        u.id,
        u.id,
      ),
      reviews: all(
        "SELECT * FROM flashcard_reviews WHERE user_id=? ORDER BY reviewed_at",
        u.id,
      ),
      weakTopics: all(
        "SELECT q.topic,count(*) mistakes FROM quiz_answers a JOIN quiz_attempts t ON t.id=a.attempt_id JOIN questions q ON q.id=a.question_id WHERE t.user_id=? AND a.answer!=q.answer GROUP BY q.topic ORDER BY mistakes DESC LIMIT 8",
        u.id,
      ),
    };
  });
  app.get("/admin/users", async (req) => {
    admin(req);
    const q = z
      .object({
        search: z.string().max(100).default(""),
        offset: z.coerce.number().int().min(0).default(0),
        limit: z.coerce.number().int().min(1).max(100).default(50),
      })
      .parse(req.query);
    const total = get(
      "SELECT count(*) n FROM users WHERE email LIKE ? OR name LIKE ?",
      `%${q.search}%`,
      `%${q.search}%`,
    ).n;
    return {
      total,
      hasMore: q.offset + q.limit < total,
      nextOffset: q.offset + q.limit,
      users: all(
        "SELECT id,email,name,role,created_at FROM users WHERE email LIKE ? OR name LIKE ? ORDER BY created_at DESC,id LIMIT ? OFFSET ?",
        `%${q.search}%`,
        `%${q.search}%`,
        q.limit,
        q.offset,
      ).map((u) => ({
        ...u,
        plan: plan(u.id),
        storage: get(
          "SELECT coalesce(sum(d.bytes),0) n FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE s.user_id=?",
          u.id,
        ).n,
      })),
    };
  });
  app.get("/admin/users/:id", async (req) => {
    admin(req);
    const uid = (req.params as any).id,
      u = get(
        "SELECT id,email,name,role,created_at FROM users WHERE id=?",
        uid,
      );
    if (!u) fail(404, "Student not found.");
    return {
      user: u,
      plan: plan(uid),
      subscription:
        get("SELECT * FROM subscriptions WHERE user_id=?", uid) || null,
      sets: get(
        "SELECT count(*) n FROM study_sets WHERE user_id=? AND deleted=0 AND parent_notebook_id IS NULL",
        uid,
      ).n,
      attempts: get("SELECT count(*) n FROM quiz_attempts WHERE user_id=?", uid)
        .n,
      storage: get(
        "SELECT coalesce(sum(d.bytes),0) n FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE s.user_id=?",
        uid,
      ).n,
      usage: all(
        "SELECT day,status,count(*) count FROM generation_usage WHERE user_id=? GROUP BY day,status ORDER BY day DESC LIMIT 60",
        uid,
      ),
    };
  });
  app.put("/admin/users/:id/pro", async (req) => {
    const a = admin(req),
      uid = (req.params as any).id,
      b = z
        .object({
          enabled: z.boolean(),
          expiresAt: z.number().int().positive().optional(),
          startsAt: z.number().int().positive().optional(),
        })
        .parse(req.body);
    if (!get("SELECT id FROM users WHERE id=?", uid))
      fail(404, "Student not found.");
    if (b.enabled && (!b.expiresAt || b.expiresAt <= now()))
      fail(400, "Set a future expiration date.");
    const startsAt = b.startsAt ?? now();
    if (b.enabled && b.expiresAt! <= startsAt)
      fail(400, "Pro expiration must follow its activation date.");
    db.transaction(() => {
      if (b.enabled)
        run(
          "INSERT INTO subscriptions VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET starts_at=excluded.starts_at,expires_at=excluded.expires_at",
          uid,
          startsAt,
          b.expiresAt!,
        );
      else run("DELETE FROM subscriptions WHERE user_id=?", uid);
      run(
        "INSERT INTO admin_audit_logs VALUES(?,?,?,?,?)",
        id(),
        a.id,
        uid,
        b.enabled ? `grant_pro:${startsAt}:${b.expiresAt}` : "revoke_pro",
        now(),
      );
    })();
    return { ok: true };
  });
  app.get("/admin/stats", async (req) => {
    admin(req);
    return {
      students: get("SELECT count(*) n FROM users WHERE role='student'").n,
      storage: get("SELECT coalesce(sum(bytes),0) n FROM documents").n,
      documents: get("SELECT count(*) n FROM documents").n,
      usage: all(
        "SELECT day,status,count(*) count FROM generation_usage GROUP BY day,status ORDER BY day DESC LIMIT 60",
      ),
      audit: all(
        "SELECT * FROM admin_audit_logs ORDER BY created_at DESC LIMIT 100",
      ),
      errors: all(
        "SELECT * FROM application_errors ORDER BY created_at DESC LIMIT 100",
      ),
    };
  });
  const settleResetDelivery = registerPasswordRoutes(
    app,
    { db, get, run, now, fail },
    options.resetDelivery,
  );
  registerOAuthRoutes(
    app,
    { db, user, publicUser, session, get, run, now, fail },
    options.oauthAdapter,
    () =>
      !!options.resetDelivery ||
      !!(process.env.SMTP_HOST && process.env.SMTP_FROM),
  );
  registerSharingRoutes(app, { user, owned, get, all, run, now, fail });
  registerNotebookRoutes(
    app,
    { db, user, owned, get, all, run, plan, change, now, fail, uploads },
    options.notebookGenerate,
  );
  registerLearningRoutes(app, {
    db,
    user,
    owned,
    full,
    plan,
    newSet,
    softDelete,
    change,
    now,
    fail,
    get,
    all,
    run,
  });
  app.addHook("onClose", async () => {
    await settleResetDelivery();
    db.close();
  });
  return app;
}
