import type { FastifyInstance } from "fastify";
import { randomBytes, createHash } from "node:crypto";
import { hash, argon2id } from "argon2";
import { z } from "zod";
import nodemailer from "nodemailer";
import { page, publicBase } from "./pages.js";
export type ResetDelivery = (email: string, url: string) => Promise<void>;
export const smtpConfigured = () =>
  !!(process.env.SMTP_HOST && process.env.SMTP_FROM);
