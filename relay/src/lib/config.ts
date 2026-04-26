/**
 * Runtime configuration — read once from process.env at boot, then immutable.
 * The admin UI edits the mutable `SettingsStore` (src/lib/store/settings.ts)
 * for anything that doesn't affect process boot (ports, bind address, etc).
 */

import path from "node:path";

function env(key: string, fallback = ""): string {
  return process.env[key] ?? fallback;
}

const rawBillingMode = env("RELAY_BILLING_MODE", "stub");
const billingMode = (
  rawBillingMode === "strict" || rawBillingMode === "apple" ? rawBillingMode : "stub"
) as "stub" | "strict" | "apple";

export const config = {
  port: Number(env("PORT", "8787")),
  dataDir: path.resolve(env("RELAY_DATA_DIR", "./data")),
  geminiApiKey: env("GEMINI_API_KEY"),
  geminiBaseUrl: env("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com"),
  relayBearerToken: env("RELAY_BEARER_TOKEN"),
  sessionSecret: env("RELAY_SESSION_SECRET"),
  adminUser: env("RELAY_ADMIN_USER", "admin"),
  adminPassword: env("RELAY_ADMIN_PASSWORD"),
  billingMode,
  debugLogging: env("RELAY_DEBUG_LOGGING", "0") === "1",
  insecureCookie: env("RELAY_INSECURE_COOKIE", "0") === "1",
  nodeEnv: env("NODE_ENV", "development"),
} as const;

/**
 * Production-only assertions. Throw at module load when any critical secret
 * is missing/short or when an insecure dev fallback is left enabled.
 */
function assertProductionSafe(): void {
  if (config.nodeEnv !== "production") return;
  const errors: string[] = [];
  if (!config.sessionSecret || Buffer.byteLength(config.sessionSecret, "utf8") < 32) {
    errors.push("RELAY_SESSION_SECRET must be set and >= 32 bytes in production.");
  }
  if (config.billingMode !== "apple") {
    errors.push("RELAY_BILLING_MODE must equal 'apple' in production (got '" + config.billingMode + "').");
  }
  if (config.insecureCookie) {
    errors.push("RELAY_INSECURE_COOKIE must not be enabled in production.");
  }
  if (errors.length > 0) {
    throw new Error("[relay-config] " + errors.join(" | "));
  }
}
assertProductionSafe();

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
