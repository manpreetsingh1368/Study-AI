import type { FastifyInstance } from "fastify";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
// Shared context keeps all mutations on the same synchronous transaction connection.
export function registerLearningRoutes(app: FastifyInstance, ctx: any) {
  const {
    db,
    user,
    owned,
    full,
    plan,
    newSet,
    change,
    now,
    fail,
    get,
    all,
    run,
  } = ctx;
  const attempt = (id: string) => {
    const a = get(
      "SELECT a.*,s.title FROM quiz_attempts a JOIN study_sets s ON s.id=a.set_id WHERE a.id=?",
      id,
    );
    return {
      ...a,
      questions: all(
        "SELECT q.*,a.answer selected FROM quiz_answers a JOIN questions q ON q.id=a.question_id WHERE a.attempt_id=? ORDER BY q.position",
        id,
      ).map((q: any) => ({ ...q, choices: JSON.parse(q.choices) })),
    };
  };
  app.post("/sync/mutate", async (req) => {
    const u = user(req),
      b = z
        .object({
          id: z.uuid(),
          kind: z.enum(["create", "update", "delete"]),
          setId: z.uuid(),
          baseVersion: z.number().int().min(0),
          title: z.string().trim().min(1).max(200).optional(),
          notes: z.string().max(100000).optional(),
          folder: z.string().trim().max(80).default(""),
        })
        .parse(req.body);
    const fingerprint = createHash("sha256")
      .update(JSON.stringify(b))
      .digest("hex");
    return db.transaction(() => {
      const receipt = get(
        "SELECT * FROM mutation_receipts WHERE user_id=? AND operation_id=?",
        u.id,
        b.id,
      );
      if (receipt) {
        if (receipt.payload_hash !== fingerprint)
          fail(409, "Operation identifier reused with different data.");
        const current = get(
          "SELECT * FROM study_sets WHERE id=? AND user_id=?",
          b.setId,
          u.id,
        );
        return {
          set: current && !current.deleted ? full(current) : null,
          setId: b.setId,
        };
      }
      if (b.kind === "create") {
        if (
          b.baseVersion !== 0 ||
          get("SELECT id FROM study_sets WHERE id=?", b.setId)
        )
          fail(
            409,
            "This study set identifier is already used. Deleted sets cannot be restored.",
          );
        if (!b.title || b.notes === undefined)
          fail(400, "Title and notes are required.");
        newSet(
          u.id,
          b.title,
          b.notes,
      } else {
        const s = owned(u.id, b.setId);
        if (s.version !== b.baseVersion)
          fail(
            409,
            "This study set changed on another device. Both versions have been preserved.",
          );
        if (b.kind === "delete") softDelete(b.setId, u.id);
        else {
          if (!b.title || b.notes === undefined)
            fail(400, "Title and notes are required.");
          run(
            "UPDATE study_sets SET title=?,notes=?,folder=?,version=version+1,updated_at=? WHERE id=?",
            b.title,
            b.notes,
            b.folder,
            now(),
            b.setId,
          );
        }
        if (b.kind !== "delete") change(b.setId, u.id);
      }
      const response = {
        set: b.kind === "delete" ? null : full(owned(u.id, b.setId)),
        setId: b.setId,
      };
      run(
        "INSERT INTO mutation_receipts VALUES(?,?,?,?)",
        u.id,
        b.id,
        fingerprint,
        JSON.stringify({ setId: b.setId }),
      );
      return response;
    })();
  });
  app.get("/sync/learning", async (req) => {
    const u = user(req),
      q = z
        .object({
          cursor: z.coerce.number().int().min(0).default(0),
          limit: z.coerce.number().int().min(1).max(100).default(50),
        })
        .parse(req.query);
    const changes = all(
      "SELECT * FROM learning_changes WHERE user_id=? AND seq>? ORDER BY seq LIMIT ?",
      u.id,
      q.cursor,
      q.limit,
    );
    return {
      changes: changes.map((c: any) => ({
        ...c,
        record:
          c.kind === "attempt"
            ? attempt(c.record_id)
            : get("SELECT * FROM flashcard_reviews WHERE id=?", c.record_id),
      })),
      cursor: changes.at(-1)?.seq ?? q.cursor,
      hasMore: changes.length === q.limit,
    };
  });
  app.get("/attempts/:id", async (req) => {
    const u = user(req),
      id = (req.params as any).id;
    const a = get("SELECT user_id FROM quiz_attempts WHERE id=?", id);
    if (!a || a.user_id !== u.id) fail(404, "Attempt not found.");
    return { attempt: attempt(id) };
  });
  app.post("/exams/start", async (req) => {
    const u = user(req),
      b = z
        .object({
          id: z.uuid(),
          setId: z.uuid(),
          collectionId: z.string().max(80),
        })
        .parse(req.body);
    const existing = get("SELECT * FROM quiz_sessions WHERE id=?", b.id);
    if (existing) {
      if (
        existing.user_id !== u.id ||
        existing.set_id !== b.setId ||
        existing.collection_id !== b.collectionId
      )
        fail(409, "Session identifier already used.");
      return { session: existing };
    }
    if (!plan(u.id).pro) fail(403, "Practice exams require Pro.");
    owned(u.id, b.setId);
    const collection = get(
      "SELECT * FROM collections WHERE id=? AND set_id=? AND kind='exam'",
      b.collectionId,
      b.setId,
    );
    if (!collection) fail(404, "Exam collection not found.");
    const qs = all(
      "SELECT id FROM questions WHERE collection_id=? ORDER BY position",
      collection.id,
    );
    if (!qs.length) fail(400, "The exam has no questions.");
    const deadline = now() + qs.length * 60000;
    run(
      "INSERT INTO quiz_sessions VALUES(?,?,?,?,?,?,?,NULL)",
      b.id,
      u.id,
      b.setId,
      collection.id,
      JSON.stringify(qs.map((q: any) => q.id)),
      now(),
      deadline,
    );
    return { session: get("SELECT * FROM quiz_sessions WHERE id=?", b.id) };
  });
  app.get("/exams/active", async (req) => {
    const u = user(req);
    return {
      sessions: all(
        "SELECT * FROM quiz_sessions WHERE user_id=? AND attempt_id IS NULL ORDER BY started_at DESC LIMIT 100",
        u.id,
      ),
    };
  });
  app.get("/analytics/advanced", async (req) => {
    const u = user(req);
    if (!plan(u.id).pro) fail(403, "Advanced analytics require Pro.");
    return {
      daily: all(
        "SELECT strftime('%Y-%m-%d',created_at/1000,'unixepoch') day,count(*) sessions,avg(score*100.0/total) average FROM quiz_attempts WHERE user_id=? GROUP BY day ORDER BY day DESC LIMIT 90",
        u.id,
      ),
      topics: all(
        "SELECT q.topic,count(*) answers,sum(CASE WHEN a.answer=q.answer THEN 1 ELSE 0 END) correct FROM quiz_answers a JOIN quiz_attempts t ON t.id=a.attempt_id JOIN questions q ON q.id=a.question_id WHERE t.user_id=? GROUP BY q.topic ORDER BY answers DESC",
        u.id,
      ),
    };
  });
}
