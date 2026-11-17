import type { FastifyInstance } from "fastify";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { z } from "zod";
import { escape, page, publicBase } from "./pages.js";
export function registerSharingRoutes(app: FastifyInstance, c: any) {
  const { user, owned, get, all, run, now, fail } = c;
  const digest = (token: string) =>
    createHash("sha256").update(token).digest("hex");
  app.get("/notebooks/:id/shares", async (req) => {
    const u = user(req),
      sid = (req.params as any).id;
    owned(u.id, sid);
    return {
      shares: all(
        "SELECT id,title,created_at,expires_at,revoked_at FROM notebook_shares WHERE notebook_id=? ORDER BY created_at DESC LIMIT 100",
        sid,
      ),
    };
  });
  app.post("/notebooks/:id/shares", async (req, reply) => {
    const u = user(req),
      sid = (req.params as any).id,
      s = owned(u.id, sid),
      b = z
        .object({
          expiresInDays: z.number().int().min(1).max(90).default(7),
          includeSourceNotes: z.boolean().default(false),
          entryIds: z.array(z.uuid()).max(20).default([]),
          noteIds: z.array(z.uuid()).max(50).default([]),
        })
        .parse(req.body);
    if (!b.includeSourceNotes && !b.entryIds.length && !b.noteIds.length)
      fail(400, "Select at least one note or response to share.");
    if (
      get(
        "SELECT count(*) n FROM notebook_shares WHERE notebook_id=? AND revoked_at IS NULL AND expires_at>?",
