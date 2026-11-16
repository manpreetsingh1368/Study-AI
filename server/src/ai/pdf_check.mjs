// Isolated validator: the parent enforces time/memory limits and supplies a
// server-generated private path, never a user-controlled command or filename.
import { readFileSync } from "node:fs";
import { PDFDocument } from "pdf-lib";
try {
  const pdf = await PDFDocument.load(readFileSync(process.argv[2]), {
    ignoreEncryption: false,
    throwOnInvalidObject: true,
  });
  const count = pdf.getPageCount();
  if (count < 1 || count > Number(process.argv[3])) process.exit(2);
  process.stdout.write(JSON.stringify({ pages: count }));
} catch {
  process.exit(2);
}
