import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
export type SourceChunk = {
  id: string;
  setId: string;
  sourceId: string;
  title: string;
