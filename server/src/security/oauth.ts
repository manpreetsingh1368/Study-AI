import type { FastifyInstance } from "fastify";
import {
  randomBytes,
  randomUUID,
  createHash,
  timingSafeEqual,
} from "node:crypto";
import { readFileSync } from "node:fs";
import { hash, verify, argon2id } from "argon2";
import { createRemoteJWKSet, jwtVerify, SignJWT, importPKCS8 } from "jose";
import { z } from "zod";
import { page, publicBase } from "./pages.js";
import { smtpConfigured } from "./password.js";
type Provider = "google" | "apple";
