import { randomBytes } from "node:crypto";
export const escape = (value: unknown) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
export function page(reply: any, title: string, body: string, script = "") {
  const nonce = randomBytes(18).toString("base64url");
  reply
    .header("Cache-Control", "no-store")
    .header("Referrer-Policy", "no-referrer")
    .header("X-Robots-Tag", "noindex, nofollow")
    .header(
      "Content-Security-Policy",
      `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`,
    );
  return reply
