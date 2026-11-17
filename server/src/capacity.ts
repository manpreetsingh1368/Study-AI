export const NOTEBOOK_SOURCE_LIMIT = 50;
export const NOTEBOOK_NOTE_LIMIT = 50;
export const NOTEBOOK_PDF_BYTES = 2 * 1024 * 1024 * 1024;
export const FILE_PDF_BYTES = () =>
  Number(process.env.MAX_PDF_BYTES || 104857600);
