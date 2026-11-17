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
