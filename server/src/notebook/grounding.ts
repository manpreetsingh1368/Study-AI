import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
export type SourceChunk = {
  id: string;
  setId: string;
  sourceId: string;
  title: string;
  version: number;
  page: number | null;
  text: string;
};
const normalize = (text: string) =>
  text.normalize("NFKC").replace(/\s+/gu, " ").trim();
export const responseSchema = z.object({
  insufficientEvidence: z.boolean(),
  blocks: z
    .array(
      z.object({
        heading: z.string().max(150),
        text: z.string().min(1).max(2200),
        citations: z
          .array(
            z.object({
              chunkId: z.string().max(120),
              quote: z.string().min(12).max(700),
            }),
          )
          .min(1)
          .max(4),
      }),
    )
