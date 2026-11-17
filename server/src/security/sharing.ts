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
