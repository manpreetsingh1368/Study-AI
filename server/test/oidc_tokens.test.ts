import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, SignJWT } from "jose";
import { validateIdentityToken } from "../src/security/oauth.js";
test("OIDC signatures, issuer, audience, nonce, email verification and mandatory expiry are enforced", async () => {
  const originalGoogle = process.env.GOOGLE_CLIENT_ID,
    originalApple = process.env.APPLE_CLIENT_ID;
  process.env.GOOGLE_CLIENT_ID = "google-test-client";
  process.env.APPLE_CLIENT_ID = "apple-test-client";
  const pair = await generateKeyPair("RS256"),
    other = await generateKeyPair("RS256");
