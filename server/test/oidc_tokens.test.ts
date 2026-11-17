import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, SignJWT } from "jose";
import { validateIdentityToken } from "../src/security/oauth.js";
