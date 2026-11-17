import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, SignJWT } from "jose";
import { validateIdentityToken } from "../src/security/oauth.js";
test("OIDC signatures, issuer, audience, nonce, email verification and mandatory expiry are enforced", async () => {
  const originalGoogle = process.env.GOOGLE_CLIENT_ID,
