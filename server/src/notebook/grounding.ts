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
    .max(12),
  followUps: z.array(z.string().min(1).max(200)).max(3),
});
export type NotebookOutput = z.infer<typeof responseSchema>;
export type NotebookInput = {
  kind: "chat" | "summary" | "guide" | "faq";
  prompt: string;
  chunks: SourceChunk[];
  history: { prompt: string; answer: string }[];
};
export function validatedEvidence(output: unknown, chunks: SourceChunk[]) {
  let parsed: NotebookOutput;
  try {
    parsed = responseSchema.parse(output);
  } catch {
    throw Object.assign(
      new Error("AI returned an invalid notebook response."),
      { statusCode: 502 },
