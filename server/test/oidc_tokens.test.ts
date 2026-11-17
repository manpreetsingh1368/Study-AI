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
  async function token(
    claims: Record<string, unknown> = {},
    provider: "google" | "apple" = "google",
  ) {
    return new SignJWT({
      nonce: "expected-nonce",
      email: "student@example.com",
      email_verified: true,
      ...claims,
    })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(
        provider === "google"
          ? "https://accounts.google.com"
          : "https://appleid.apple.com",
      )
      .setAudience(
        provider === "google" ? "google-test-client" : "apple-test-client",
      )
      .setSubject("stable-provider-subject")
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(pair.privateKey);
  }
  try {
    const valid = await token();
    assert.equal(
      (
        await validateIdentityToken(
          "google",
          valid,
          "expected-nonce",
          pair.publicKey,
        )
      ).email,
      "student@example.com",
    );
    await assert.rejects(
      validateIdentityToken("google", valid, "wrong-nonce", pair.publicKey),
    );
    await assert.rejects(
      validateIdentityToken("google", valid, "expected-nonce", other.publicKey),
    );
    await assert.rejects(
      validateIdentityToken(
        "google",
        await token({ email_verified: false }),
        "expected-nonce",
        pair.publicKey,
      ),
    );
    await assert.rejects(
      validateIdentityToken(
        "google",
        await token({ azp: "untrusted-client" }),
        "expected-nonce",
        pair.publicKey,
      ),
    );
    await assert.rejects(
      validateIdentityToken("apple", valid, "expected-nonce", pair.publicKey),
    );
    process.env.GOOGLE_CLIENT_ID = "wrong-client";
    await assert.rejects(
