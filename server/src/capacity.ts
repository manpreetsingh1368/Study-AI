export const NOTEBOOK_SOURCE_LIMIT = 50;
export const NOTEBOOK_NOTE_LIMIT = 50;
export const NOTEBOOK_PDF_BYTES = 2 * 1024 * 1024 * 1024;
export const FILE_PDF_BYTES = () =>
  Number(process.env.MAX_PDF_BYTES || 104857600);
export function capacity(s: any, get: any) {
  const root = s.parent_notebook_id || s.id;
  return {
    sourceLimit: 50,
    noteLimit: 50,
    pdfLimitBytes: NOTEBOOK_PDF_BYTES,
    fileLimitBytes: FILE_PDF_BYTES(),
    sources: get(
