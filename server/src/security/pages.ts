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
    .type("text/html; charset=utf-8")
    .send(
      `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>${escape(title)} · Study AI</title><style>:root{font:16px/1.7 system-ui,sans-serif;color:#242332;background:#f7f6fb;--paper:#fff;--border:#e5e1ef;--accent:#6550bc}*{box-sizing:border-box}body{margin:0}main{max-width:860px;margin:5vh auto;padding:32px}header{color:var(--accent);font-weight:700;letter-spacing:.04em;margin-bottom:28px}article,form,.card{background:var(--paper);border:1px solid var(--border);border-radius:22px;padding:28px;margin:20px 0}h1{font-size:clamp(26px,5vw,42px);line-height:1.2;letter-spacing:-.04em}h2{font-size:20px}pre{font:inherit;white-space:pre-wrap;overflow-wrap:anywhere}label{display:block;margin:16px 0 6px}input,button{font:inherit;padding:12px 16px;border-radius:12px;border:1px solid var(--border);width:100%}button{background:var(--accent);color:white;cursor:pointer;margin-top:20px}button:disabled{opacity:.5}small,.muted{opacity:.7}a{color:var(--accent)}blockquote{border-left:3px solid var(--accent);padding-left:16px;margin-left:0}#message{overflow-wrap:anywhere}@media(prefers-color-scheme:dark){:root{color:#e8e5ef;background:#17161f;--paper:#24222e;--border:#393543;--accent:#baa7ff}button{color:#20182c}}@media(max-width:500px){main{padding:20px}article,form,.card{padding:20px}}</style></head><body><main><header>✦ Study AI</header>${body}<p class="muted"><small>Your learning. Your workspace.</small></p></main>${script ? `<script nonce="${nonce}">${script}</script>` : ""}</body></html>`,
    );
