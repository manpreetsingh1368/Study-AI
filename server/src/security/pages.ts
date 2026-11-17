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
