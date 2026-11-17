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
