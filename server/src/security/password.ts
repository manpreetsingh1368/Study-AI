import type { FastifyInstance } from "fastify";
import { randomBytes, createHash } from "node:crypto";
import { hash, argon2id } from "argon2";
import { z } from "zod";
import nodemailer from "nodemailer";
import { page, publicBase } from "./pages.js";
export type ResetDelivery = (email: string, url: string) => Promise<void>;
export const smtpConfigured = () =>
  !!(process.env.SMTP_HOST && process.env.SMTP_FROM);
export const sendReset: ResetDelivery = async (email, url) => {
  const transport = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: process.env.SMTP_SECURE === "true",
    requireTLS: process.env.SMTP_SECURE !== "true",
    auth: process.env.SMTP_USER
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD }
      : undefined,
    connectionTimeout: 10000,
    socketTimeout: 15000,
  });
  try {
    await transport.sendMail({
      from: process.env.SMTP_FROM,
      to: email,
      subject: "Reset your Study AI password",
      text: `A password reset was requested for your Study AI account.\n\nOpen this link within 20 minutes:\n${url}\n\nIf you did not request this, ignore this message. The link can be used only once.\nStudy AI`,
    });
  } finally {
    transport.close();
  }
};
export function registerPasswordRoutes(
  app: FastifyInstance,
  c: any,
  delivery?: ResetDelivery,
) {
  const { db, get, run, now, fail } = c;
  const pending = new Set<Promise<void>>();
  const digest = (s: string) => createHash("sha256").update(s).digest("hex");
  app.post(
    "/auth/forgot-password",
    { config: { rateLimit: { max: 5, timeWindow: 60000 } } },
    async (req) => {
      const b = z
        .object({
          email: z
            .email()
            .max(254)
            .transform((s) => s.toLowerCase()),
        })
        .parse(req.body);
      const available = !!delivery || smtpConfigured();
      const response = {
        message:
          "If an account exists and email delivery is available, a password-reset link will be sent. Check your inbox and spam folder.",
        deliveryAvailable: available,
      };
      if (!available) return response;
      const u = get("SELECT id FROM users WHERE email=?", b.email);
      if (!u) return response;
      if (
        get(
          "SELECT token_hash FROM password_resets WHERE user_id=? AND created_at>?",
          u.id,
          now() - 60000,
        )
      )
        return response;
      const token = randomBytes(32).toString("base64url"),
        tokenHash = digest(token);
      db.transaction(() => {
        run(
          "UPDATE password_resets SET used_at=? WHERE user_id=? AND used_at IS NULL",
          now(),
          u.id,
        );
        run(
          "INSERT INTO password_resets VALUES(?,?,?,NULL,?)",
          tokenHash,
          u.id,
          now() + 1200000,
          now(),
        );
      })();
      const job = new Promise<void>((resolve) => setImmediate(resolve))
        .then(() =>
          (delivery || sendReset)(
            b.email,
            `${publicBase()}/reset-password#token=${token}`,
          ),
        )
        .catch(() => {
          run("DELETE FROM password_resets WHERE token_hash=?", tokenHash);
          run(
            "INSERT INTO application_errors VALUES(?,?,?)",
            randomBytes(16).toString("hex"),
            "RESET_DELIVERY_FAILED",
            now(),
          );
        });
      pending.add(job);
      void job.finally(() => pending.delete(job));
      return response;
    },
  );
  app.post(
    "/auth/reset-password",
    { config: { rateLimit: { max: 8, timeWindow: 60000 } } },
    async (req) => {
      const b = z
        .object({
          token: z.string().min(30).max(100),
          password: z.string().min(12).max(128),
        })
        .parse(req.body);
      const passwordHash = await hash(b.password, { type: argon2id });
      db.transaction(() => {
        const reset = get(
          "SELECT * FROM password_resets WHERE token_hash=? AND used_at IS NULL AND expires_at>?",
          digest(b.token),
          now(),
        );
        if (!reset)
          fail(
            400,
            "This reset link is invalid or expired. Request a new one.",
          );
        run(
          "UPDATE users SET password_hash=?,password_enabled=1 WHERE id=?",
          passwordHash,
          reset.user_id,
        );
        run(
          "UPDATE password_resets SET used_at=? WHERE user_id=? AND used_at IS NULL",
          now(),
