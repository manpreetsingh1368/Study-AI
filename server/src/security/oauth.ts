import type { FastifyInstance } from "fastify";
import {
  randomBytes,
  randomUUID,
  createHash,
  timingSafeEqual,
} from "node:crypto";
import { readFileSync } from "node:fs";
