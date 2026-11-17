import type { FastifyInstance } from "fastify";
import { randomBytes, createHash } from "node:crypto";
import { hash, argon2id } from "argon2";
import { z } from "zod";
