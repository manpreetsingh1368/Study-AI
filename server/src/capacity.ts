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
      "SELECT count(*) n FROM study_sets WHERE parent_notebook_id=? AND deleted=0",
      root,
    ).n,
    pdfBytes: get(
      "SELECT coalesce(sum(d.bytes),0) n FROM documents d JOIN study_sets s ON s.id=d.set_id WHERE (s.id=? OR s.parent_notebook_id=?) AND s.deleted=0",
      root,
