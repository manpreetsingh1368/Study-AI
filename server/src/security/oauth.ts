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
