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
