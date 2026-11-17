import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
export async function validatePdf(path: string): Promise<void> {
  try {
    await promisify(execFile)(
      process.execPath,
      [
        `--max-old-space-size=${process.env.PDF_VALIDATOR_HEAP_MB || 384}`,
        fileURLToPath(new URL("./pdf_check.mjs", import.meta.url)),
        path,
        process.env.MAX_PDF_PAGES || "1000",
      ],
      { timeout: 8000, maxBuffer: 2048 },
    );
  } catch {
    throw Object.assign(
      new Error(
        "This PDF is invalid, encrypted, too complex, or exceeds the page limit.",
      ),
      { statusCode: 400 },
    );
  }
}
