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
