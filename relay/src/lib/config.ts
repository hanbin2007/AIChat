/**
 * Runtime configuration — read once from process.env at boot, then immutable.
 * The admin UI edits the mutable `SettingsStore` (src/lib/store/settings.ts)
 * for anything that doesn't affect process boot (ports, bind address, etc).
 */

import path from "node:path";

function env(key: string, fallback = ""): string {
  return process.env[key] ?? fallback;
}

export const config = {
  port: Number(env("PORT", "8787")),
  dataDir: path.resolve(env("RELAY_DATA_DIR", "./data")),
  geminiApiKey: env("GEMINI_API_KEY"),
  geminiBaseUrl: env("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com"),
  relayBearerToken: env("RELAY_BEARER_TOKEN"),
  sessionSecret: env("RELAY_SESSION_SECRET"),
  adminUser: env("RELAY_ADMIN_USER", "admin"),
  adminPassword: env("RELAY_ADMIN_PASSWORD"),
  billingMode: (env("RELAY_BILLING_MODE", "stub") === "strict" ? "strict" : "stub") as "stub" | "strict",
  debugLogging: env("RELAY_DEBUG_LOGGING", "0") === "1",
} as const;

export function configDiagnostics() {
  return {
    port: config.port,
    dataDir: config.dataDir,
    geminiConfigured: Boolean(config.geminiApiKey),
    bearerConfigured: Boolean(config.relayBearerToken),
    sessionSecretConfigured: Boolean(config.sessionSecret),
    adminConfigured: Boolean(config.adminPassword),
    billingMode: config.billingMode,
  };
}
