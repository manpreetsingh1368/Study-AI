import type { FastifyInstance } from "fastify";
import {
  randomBytes,
  randomUUID,
  createHash,
  timingSafeEqual,
} from "node:crypto";
import { readFileSync } from "node:fs";
import { hash, verify, argon2id } from "argon2";
import { createRemoteJWKSet, jwtVerify, SignJWT, importPKCS8 } from "jose";
import { z } from "zod";
import { page, publicBase } from "./pages.js";
import { smtpConfigured } from "./password.js";
type Provider = "google" | "apple";
export type Identity = { subject: string; email: string; name: string };
export type OAuthAdapter = {
  enabled: (provider: Provider) => boolean;
  authorization: (provider: Provider, flow: any) => string;
  exchange: (provider: Provider, code: string, flow: any) => Promise<Identity>;
};
const digest = (value: string) =>
  createHash("sha256").update(value).digest("hex");
const googleKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);
const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);
export async function validateIdentityToken(
  provider: Provider,
  token: string,
  nonce: string,
  verificationKey?: CryptoKey,
) {
  const { payload } = await jwtVerify(
    token,
    verificationKey ?? (provider === "google" ? googleKeys : appleKeys),
    {
      issuer:
        provider === "google"
          ? ["https://accounts.google.com", "accounts.google.com"]
          : "https://appleid.apple.com",
      audience:
        provider === "google"
          ? process.env.GOOGLE_CLIENT_ID
          : process.env.APPLE_CLIENT_ID,
      algorithms: ["RS256"],
      requiredClaims: ["exp", "iat", "sub", "nonce", "email", "email_verified"],
      maxTokenAge: "10m",
      clockTolerance: 5,
    },
  );
  const audience =
    provider === "google"
      ? process.env.GOOGLE_CLIENT_ID
      : process.env.APPLE_CLIENT_ID;
  if (payload.azp && payload.azp !== audience)
    throw new Error("Invalid authorized party.");
  if (
    payload.nonce !== nonce ||
    typeof payload.sub !== "string" ||
    !payload.sub ||
    payload.sub.length > 255
  )
    throw new Error("Invalid identity nonce.");
  if (payload.email_verified !== true && payload.email_verified !== "true")
    throw new Error("A verified provider email is required.");
  const email = z.email().max(254).parse(payload.email).toLowerCase();
  return {
    subject: payload.sub,
    email,
    name:
      typeof payload.name === "string"
        ? payload.name.slice(0, 100)
        : provider === "apple"
          ? "Student"
          : email.split("@")[0],
  };
}
export const productionOAuth: OAuthAdapter = {
  enabled: (provider) =>
    provider === "google"
      ? !!(
          process.env.GOOGLE_CLIENT_ID &&
          process.env.GOOGLE_CLIENT_SECRET &&
          process.env.PUBLIC_BASE_URL
        )
      : !!(
          process.env.APPLE_CLIENT_ID &&
          process.env.APPLE_TEAM_ID &&
          process.env.APPLE_KEY_ID &&
          (process.env.APPLE_PRIVATE_KEY ||
            process.env.APPLE_PRIVATE_KEY_PATH) &&
          process.env.PUBLIC_BASE_URL?.startsWith("https://")
        ),
  authorization(provider, flow) {
    const parameters = new URLSearchParams({
      client_id:
        provider === "google"
          ? process.env.GOOGLE_CLIENT_ID!
          : process.env.APPLE_CLIENT_ID!,
      redirect_uri: `${publicBase()}/auth/oauth/${provider}/callback`,
      response_type: "code",
      scope: provider === "google" ? "openid email profile" : "name email",
      state: flow.state,
      nonce: flow.nonce,
    });
    if (provider === "google") {
      parameters.set(
        "code_challenge",
        createHash("sha256").update(flow.pkce_verifier).digest("base64url"),
      );
      parameters.set("code_challenge_method", "S256");
      parameters.set("prompt", "select_account");
    } else parameters.set("response_mode", "form_post");
    return `${provider === "google" ? "https://accounts.google.com/o/oauth2/v2/auth" : "https://appleid.apple.com/auth/authorize"}?${parameters}`;
  },
  async exchange(provider, code, flow) {
    let secret = process.env.GOOGLE_CLIENT_SECRET!;
    if (provider === "apple") {
      const pem = (
        process.env.APPLE_PRIVATE_KEY ||
        (process.env.APPLE_PRIVATE_KEY_PATH
          ? readFileSync(process.env.APPLE_PRIVATE_KEY_PATH, "utf8")
          : "")
      ).replace(/\\n/g, "\n");
      secret = await new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: process.env.APPLE_KEY_ID! })
        .setIssuer(process.env.APPLE_TEAM_ID!)
        .setSubject(process.env.APPLE_CLIENT_ID!)
        .setAudience("https://appleid.apple.com")
        .setIssuedAt()
        .setExpirationTime("5m")
        .sign(await importPKCS8(pem, "ES256"));
    }
    const body = new URLSearchParams({
      client_id:
        provider === "google"
          ? process.env.GOOGLE_CLIENT_ID!
          : process.env.APPLE_CLIENT_ID!,
      client_secret: secret,
      code,
      grant_type: "authorization_code",
      redirect_uri: `${publicBase()}/auth/oauth/${provider}/callback`,
    });
    if (provider === "google") body.set("code_verifier", flow.pkce_verifier);
    const response = await fetch(
      provider === "google"
        ? "https://oauth2.googleapis.com/token"
        : "https://appleid.apple.com/auth/token",
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok) throw new Error("Provider exchange failed.");
    const data: any = await response.json();
    return validateIdentityToken(provider, data.id_token, flow.nonce);
  },
};
export function registerOAuthRoutes(
  app: FastifyInstance,
  c: any,
  adapter = productionOAuth,
  resetConfigured = smtpConfigured,
) {
  const { db, user, publicUser, session, get, run, now, fail } = c;
  app.get("/auth/options", async () => ({
    google: adapter.enabled("google"),
    apple: adapter.enabled("apple"),
    passwordReset: resetConfigured(),
  }));
  async function start(req: any, provider: Provider, link = false) {
    if (!adapter.enabled(provider))
      fail(
        503,
        `${provider === "google" ? "Google" : "Apple"} sign-in is not configured on this server.`,
      );
    const body = z
      .object({
        challenge: z.string().regex(/^[a-f0-9]{64}$/),
        password: z.string().max(128).optional(),
      })
      .parse(req.body);
    let owner: any = null,
      sessionHash: string | null = null;
    if (link) {
      owner = user(req);
      sessionHash = digest(req.headers.authorization.slice(7));
      const current = get(
        "SELECT created_at FROM sessions WHERE token_hash=?",
        sessionHash,
      );
      if (owner.password_enabled) {
        if (
          !body.password ||
          !(await verify(owner.password_hash, body.password))
        )
          fail(401, "Enter your current password to connect an identity.");
      } else if (!current || current.created_at < now() - 300000)
        fail(401, "Sign in again before connecting another provider.");
    }
    const flowId = randomUUID(),
      state = randomBytes(32).toString("base64url"),
      nonce = randomBytes(32).toString("base64url"),
      pkce = randomBytes(32).toString("base64url"),
      launch = randomBytes(32).toString("base64url");
    run(
      "INSERT INTO oauth_flows(id,provider,state_hash,nonce,pkce_verifier,client_challenge,expires_at,link_user_id,link_session_hash,launch_hash) VALUES(?,?,?,?,?,?,?,?,?,?)",
      flowId,
      provider,
      digest(state),
      nonce,
      pkce,
      body.challenge,
      now() + 600000,
      owner?.id || null,
      sessionHash,
      digest(launch),
    );
    // State is needed at authorization time but is never placed in a polling response.
    return {
      flowId,
      url: `${publicBase()}/auth/oauth/${provider}/begin?flow=${flowId}&key=${launch}&state=${state}`,
      expiresAt: now() + 600000,
    };
  }
  for (const provider of ["google", "apple"] as const) {
    app.post(
      `/auth/oauth/${provider}/start`,
      { config: { rateLimit: { max: 10, timeWindow: 60000 } } },
      (req) => start(req, provider),
    );
    app.post(
      `/me/identities/${provider}/start`,
      { config: { rateLimit: { max: 10, timeWindow: 60000 } } },
      (req) => start(req, provider, true),
    );
    app.get(`/auth/oauth/${provider}/begin`, async (req, reply) => {
      const q = z
        .object({
          flow: z.uuid(),
          key: z.string().min(30).max(100),
          state: z.string().min(30).max(100),
        })
        .parse(req.query);
      const flow = get(
        "SELECT * FROM oauth_flows WHERE id=? AND provider=? AND expires_at>? AND status='pending' AND launched=0",
        q.flow,
        provider,
        now(),
      );
      if (
        !flow ||
        flow.launch_hash !== digest(q.key) ||
        flow.state_hash !== digest(q.state)
      )
        fail(
          400,
          "This sign-in request is invalid or expired. Start again in the app.",
        );
      run("UPDATE oauth_flows SET launched=1 WHERE id=?", flow.id);
      const secure = publicBase().startsWith("https://");
      reply
        .header(
          "Set-Cookie",
          `study_oauth_${flow.id.replaceAll("-", "")}=${q.key}; HttpOnly; Path=/auth/oauth/${provider}; Max-Age=600; SameSite=${provider === "apple" ? "None" : "Lax"}${secure ? "; Secure" : ""}`,
        )
        .header("Cache-Control", "no-store")
        .header("Referrer-Policy", "no-referrer");
      return reply.redirect(
        adapter.authorization(provider, { ...flow, state: q.state }),
      );
    });
    const callback = async (req: any, reply: any) => {
      const b = z
