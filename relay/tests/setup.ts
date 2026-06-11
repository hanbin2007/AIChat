/**
 * Global test setup — runs once per Vitest worker, BEFORE any module under
 * src/ is imported. Sets env vars so `@/lib/config` picks safe defaults and
 * every test starts with an isolated per-worker temp data directory.
 */

import { mkdtempSync } from "node:fs";
import path from "node:path";
import os from "node:os";
import { vi } from "vitest";

const tmpDir = mkdtempSync(path.join(os.tmpdir(), "relay-test-"));
process.env.RELAY_DATA_DIR = tmpDir;
process.env.GEMINI_API_KEY = "test-gemini-key";
process.env.RELAY_BEARER_TOKEN = "test-bearer-token";
process.env.RELAY_SESSION_SECRET = "0".repeat(64);
process.env.RELAY_ADMIN_USER = "admin";
process.env.RELAY_ADMIN_PASSWORD = "testpassword";
process.env.RELAY_BILLING_MODE = "stub";
process.env.RELAY_DEBUG_LOGGING = "0";
process.env.PORT = "8787";
// JWS verification defaults ON in production. The test fixtures use forged,
// unsigned JWS strings (see forgeJws in helpers.ts), so disable cryptographic
// verification globally here. The dedicated jws.test.ts opts verification back
// in per-case with a real self-signed ES256 chain.
process.env.BILLING_JWS_VERIFY = "false";

// A tiny in-memory substitute for next/headers' cookies() so admin auth
// routes can be exercised from Vitest without the Next.js runtime context.
// Values are reset between tests via resetMockCookies() in helpers.ts.
const cookieJar = new Map<string, string>();
(globalThis as unknown as { __cookieJar: Map<string, string> }).__cookieJar = cookieJar;

vi.mock("next/headers", () => ({
  cookies: async () => ({
    get: (name: string) =>
      cookieJar.has(name) ? { name, value: cookieJar.get(name)! } : undefined,
    set: (name: string, value: string) => {
      cookieJar.set(name, value);
    },
    delete: (name: string) => {
      cookieJar.delete(name);
    },
  }),
}));
