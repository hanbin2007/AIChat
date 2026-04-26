/**
 * Operator-editable runtime settings. Persisted alongside billing state so a
 * single volume backup captures the whole relay.
 */

import path from "node:path";
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { config } from "@/lib/config";
import { hashPassword, verifyPassword } from "@/lib/auth/password";
import { newBearerToken, uuid } from "@/lib/ids";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "./persistence";

/**
 * Hash an admin bearer token for at-rest storage. Uses SHA-256 with a per-token
 * salt; the relay's blast radius from a leaked file is limited to brute-force
 * rather than direct compromise.
 */
export function hashAdminToken(plain: string, salt: string): string {
  return createHash("sha256").update(`${salt}::${plain}`).digest("base64url");
}

/** Constant-time compare two base64url hashes of equal length. */
export function adminTokenMatches(plain: string, token: AdminToken): boolean {
  if (!token.valueHash || !token.valueSalt) return false;
  const expected = Buffer.from(token.valueHash);
  const got = Buffer.from(hashAdminToken(plain, token.valueSalt));
  if (expected.length !== got.length) return false;
  return timingSafeEqual(expected, got);
}

export interface AdminUser {
  id: string;
  username: string;
  role: "operator" | "support" | "viewer";
  passwordHash: string;
  createdAt: string;
  lastLoginAt?: string;
}

export interface AdminToken {
  id: string;
  label: string;
  prefix: string;
  /** SHA-256 over `salt::plaintext`. Only the hash is persisted to disk. */
  valueHash: string;
  /** Per-token salt used to derive the hash. */
  valueSalt: string;
  /** First 8 chars of the plaintext token, used for log correlation. */
  valuePrefix: string;
  scope: "admin" | "client";
  rpmLimit?: number;
  concurrentStreams?: number;
  allowedEndpoints?: string[];
  ipAllowlist?: string[];
  expiresAt?: string;
  createdAt: string;
  lastUsedAt?: string;
  revoked?: boolean;
  /**
   * @deprecated Plaintext storage. Always undefined on freshly written records;
   * may be present on disk during the one-time migration. Do not reintroduce.
   */
  value?: string;
}

export interface IssuedAdminToken {
  /** Persisted record (hash only). */
  token: AdminToken;
  /** Plaintext bearer; returned ONCE on creation, never persisted again. */
  plaintext: string;
}

export interface SettingsSnapshot {
  gateway: {
    allowLanClients: boolean;
    corsOrigins: string[];
    requestBodyLimitMB: number;
  };
  upstream: {
    geminiBaseUrlOverride?: string;
    timeoutMs: number;
    retries: number;
    retryMode: "none" | "linear" | "exponential";
    healthProbeIntervalMs: number;
    modelAllowlist?: string[];
  };
  auth: {
    sessionTtlMinutes: number;
  };
  rateLimits: {
    globalRpm: number;
    perTokenRpm: number;
    concurrentStreams: number;
    perIpRpm: number;
    ipAllowlist: string[];
    ipBlocklist: string[];
  };
  billing: {
    mode: "stub" | "strict";
    trialEnabled: boolean;
    subscriptionEnabled: boolean;
    offlineEnabled: boolean;
  };
  observability: {
    activityLogSize: number;
    debugLogSize: number;
    debugLoggingEnabled: boolean;
    logSamplingRate: number;
    auditRetentionDays: number;
    prometheusEnabled: boolean;
    openTelemetryEndpoint?: string;
    redactionRules: { name: string; pattern: string; enabled: boolean }[];
  };
  localization: {
    defaultLocale: "zh-Hans" | "en";
    timezone: string;
  };
  adminUsers: AdminUser[];
  adminTokens: AdminToken[];
}

function emptySnapshot(): SettingsSnapshot {
  return {
    gateway: { allowLanClients: true, corsOrigins: [], requestBodyLimitMB: 16 },
    upstream: {
      timeoutMs: 60_000,
      retries: 2,
      retryMode: "exponential",
      healthProbeIntervalMs: 60_000,
    },
    auth: { sessionTtlMinutes: 24 * 60 },
    rateLimits: {
      globalRpm: 3000,
      perTokenRpm: 300,
      concurrentStreams: 32,
      perIpRpm: 600,
      ipAllowlist: [],
      ipBlocklist: [],
    },
    billing: {
      mode: config.billingMode === "stub" ? "stub" : "strict",
      trialEnabled: true,
      subscriptionEnabled: true,
      offlineEnabled: true,
    },
    observability: {
      activityLogSize: 500,
      debugLogSize: 300,
      debugLoggingEnabled: config.debugLogging,
      logSamplingRate: 1,
      auditRetentionDays: 90,
      prometheusEnabled: false,
      redactionRules: [
        { name: "Bearer token", pattern: "Bearer\\s+[A-Za-z0-9_-]+", enabled: true },
        { name: "Gemini API key", pattern: "AIza[0-9A-Za-z_-]{20,}", enabled: true },
      ],
    },
    localization: { defaultLocale: "zh-Hans", timezone: "Asia/Shanghai" },
    adminUsers: [],
    adminTokens: [],
  };
}

const FILE = () => path.join(config.dataDir, "settings.json");

/**
 * Explicit field-level merge. Avoids `Object.assign(target, untrustedPatch)`
 * which would let an attacker introduce arbitrary keys.
 */
function mergeSettings(current: SettingsSnapshot, patch: Partial<SettingsSnapshot>): SettingsSnapshot {
  const out: SettingsSnapshot = JSON.parse(JSON.stringify(current));
  if (patch.gateway) {
    if (typeof patch.gateway.allowLanClients === "boolean") out.gateway.allowLanClients = patch.gateway.allowLanClients;
    if (Array.isArray(patch.gateway.corsOrigins)) out.gateway.corsOrigins = patch.gateway.corsOrigins.slice();
    if (typeof patch.gateway.requestBodyLimitMB === "number") out.gateway.requestBodyLimitMB = patch.gateway.requestBodyLimitMB;
  }
  if (patch.upstream) {
    if (typeof patch.upstream.geminiBaseUrlOverride === "string" || patch.upstream.geminiBaseUrlOverride === undefined) {
      out.upstream.geminiBaseUrlOverride = patch.upstream.geminiBaseUrlOverride;
    }
    if (typeof patch.upstream.timeoutMs === "number") out.upstream.timeoutMs = patch.upstream.timeoutMs;
    if (typeof patch.upstream.retries === "number") out.upstream.retries = patch.upstream.retries;
    if (patch.upstream.retryMode) out.upstream.retryMode = patch.upstream.retryMode;
    if (typeof patch.upstream.healthProbeIntervalMs === "number") out.upstream.healthProbeIntervalMs = patch.upstream.healthProbeIntervalMs;
    if (Array.isArray(patch.upstream.modelAllowlist)) out.upstream.modelAllowlist = patch.upstream.modelAllowlist.slice();
  }
  if (patch.auth) {
    if (typeof patch.auth.sessionTtlMinutes === "number") out.auth.sessionTtlMinutes = patch.auth.sessionTtlMinutes;
  }
  if (patch.rateLimits) {
    if (typeof patch.rateLimits.globalRpm === "number") out.rateLimits.globalRpm = patch.rateLimits.globalRpm;
    if (typeof patch.rateLimits.perTokenRpm === "number") out.rateLimits.perTokenRpm = patch.rateLimits.perTokenRpm;
    if (typeof patch.rateLimits.concurrentStreams === "number") out.rateLimits.concurrentStreams = patch.rateLimits.concurrentStreams;
    if (typeof patch.rateLimits.perIpRpm === "number") out.rateLimits.perIpRpm = patch.rateLimits.perIpRpm;
    if (Array.isArray(patch.rateLimits.ipAllowlist)) out.rateLimits.ipAllowlist = patch.rateLimits.ipAllowlist.slice();
    if (Array.isArray(patch.rateLimits.ipBlocklist)) out.rateLimits.ipBlocklist = patch.rateLimits.ipBlocklist.slice();
  }
  if (patch.billing) {
    if (patch.billing.mode === "stub" || patch.billing.mode === "strict") out.billing.mode = patch.billing.mode;
    if (typeof patch.billing.trialEnabled === "boolean") out.billing.trialEnabled = patch.billing.trialEnabled;
    if (typeof patch.billing.subscriptionEnabled === "boolean") out.billing.subscriptionEnabled = patch.billing.subscriptionEnabled;
    if (typeof patch.billing.offlineEnabled === "boolean") out.billing.offlineEnabled = patch.billing.offlineEnabled;
  }
  if (patch.observability) {
    if (typeof patch.observability.activityLogSize === "number") out.observability.activityLogSize = patch.observability.activityLogSize;
    if (typeof patch.observability.debugLogSize === "number") out.observability.debugLogSize = patch.observability.debugLogSize;
    if (typeof patch.observability.debugLoggingEnabled === "boolean") out.observability.debugLoggingEnabled = patch.observability.debugLoggingEnabled;
    if (typeof patch.observability.logSamplingRate === "number") out.observability.logSamplingRate = patch.observability.logSamplingRate;
    if (typeof patch.observability.auditRetentionDays === "number") out.observability.auditRetentionDays = patch.observability.auditRetentionDays;
    if (typeof patch.observability.prometheusEnabled === "boolean") out.observability.prometheusEnabled = patch.observability.prometheusEnabled;
    if (typeof patch.observability.openTelemetryEndpoint === "string" || patch.observability.openTelemetryEndpoint === undefined) {
      out.observability.openTelemetryEndpoint = patch.observability.openTelemetryEndpoint;
    }
    if (Array.isArray(patch.observability.redactionRules)) {
      out.observability.redactionRules = patch.observability.redactionRules
        .filter((r): r is { name: string; pattern: string; enabled: boolean } =>
          !!r && typeof r === "object" && typeof r.name === "string" && typeof r.pattern === "string" && typeof r.enabled === "boolean",
        )
        .map((r) => ({ name: r.name, pattern: r.pattern, enabled: r.enabled }));
    }
  }
  if (patch.localization) {
    if (patch.localization.defaultLocale === "zh-Hans" || patch.localization.defaultLocale === "en") {
      out.localization.defaultLocale = patch.localization.defaultLocale;
    }
    if (typeof patch.localization.timezone === "string") out.localization.timezone = patch.localization.timezone;
  }
  return out;
}

class SettingsStore {
  private snapshot: SettingsSnapshot = emptySnapshot();
  private loaded = false;
  private queue = new WriteQueue();

  async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    const persisted = await readJsonFile<Partial<SettingsSnapshot>>(FILE(), {});
    this.snapshot = { ...emptySnapshot(), ...persisted } as SettingsSnapshot;
    if (this.migrateAdminTokens()) {
      // Persist the rewrite synchronously so callers don't race the WriteQueue
      // (especially the tests, which delete the data dir between cases).
      await writeJsonFileAtomic(FILE(), this.snapshot);
    }
    this.loaded = true;
  }

  async get(): Promise<SettingsSnapshot> {
    await this.ensureLoaded();
    return JSON.parse(JSON.stringify(this.snapshot));
  }

  /**
   * Synchronous snapshot accessor for hot-path callers (observability) that
   * cannot await. Returns the most-recently-loaded snapshot or null when the
   * store has not been loaded yet — callers must tolerate either.
   */
  cachedSnapshot(): SettingsSnapshot | null {
    return this.loaded ? this.snapshot : null;
  }

  private migrateAdminTokens(): boolean {
    let mutated = false;
    for (const t of this.snapshot.adminTokens) {
      const legacy = t as AdminToken & { value?: string };
      if (legacy.value && !t.valueHash) {
        const salt = randomBytes(16).toString("hex");
        const hash = hashAdminToken(legacy.value, salt);
        t.valueHash = hash;
        t.valueSalt = salt;
        t.valuePrefix = legacy.value.slice(0, 8);
        delete legacy.value;
        mutated = true;
      } else if (legacy.value) {
        delete legacy.value;
        mutated = true;
      }
    }
    return mutated;
  }

  async update(patch: Partial<SettingsSnapshot>): Promise<void> {
    await this.queue.run(async () => {
      await this.ensureLoaded();
      this.snapshot = mergeSettings(this.snapshot, patch);
      await writeJsonFileAtomic(FILE(), this.snapshot);
    });
  }

  async isSetupComplete(): Promise<boolean> {
    await this.ensureLoaded();
    return this.snapshot.adminUsers.length > 0;
  }

  async seedAdmin(username: string, password: string, role: AdminUser["role"] = "operator"): Promise<AdminUser> {
    return this.queue.run(async () => {
      await this.ensureLoaded();
      const user: AdminUser = {
        id: uuid(),
        username,
        role,
        passwordHash: hashPassword(password),
        createdAt: new Date().toISOString(),
      };
      this.snapshot.adminUsers.push(user);
      await writeJsonFileAtomic(FILE(), this.snapshot);
      return user;
    });
  }

  async authenticateAdmin(username: string, password: string): Promise<AdminUser | null> {
    await this.ensureLoaded();
    const user = this.snapshot.adminUsers.find((u) => u.username === username);
    if (!user) return null;
    if (!verifyPassword(password, user.passwordHash)) return null;
    user.lastLoginAt = new Date().toISOString();
    await writeJsonFileAtomic(FILE(), this.snapshot);
    return user;
  }

  async issueToken(
    params: Omit<AdminToken, "id" | "valueHash" | "valueSalt" | "valuePrefix" | "prefix" | "createdAt">,
  ): Promise<IssuedAdminToken> {
    return this.queue.run(async () => {
      await this.ensureLoaded();
      const plaintext = newBearerToken();
      const salt = randomBytes(16).toString("hex");
      const token: AdminToken = {
        ...params,
        id: uuid(),
        prefix: plaintext.slice(0, 8),
        valuePrefix: plaintext.slice(0, 8),
        valueHash: hashAdminToken(plaintext, salt),
        valueSalt: salt,
        createdAt: new Date().toISOString(),
      };
      this.snapshot.adminTokens.push(token);
      await writeJsonFileAtomic(FILE(), this.snapshot);
      return { token, plaintext };
    });
  }

  /** Find a non-revoked admin token whose hash matches the supplied plaintext. */
  async findAdminTokenByPlaintext(plain: string): Promise<AdminToken | undefined> {
    await this.ensureLoaded();
    for (const t of this.snapshot.adminTokens) {
      if (t.revoked) continue;
      if (adminTokenMatches(plain, t)) return t;
    }
    return undefined;
  }

  async revokeToken(id: string): Promise<void> {
    await this.queue.run(async () => {
      await this.ensureLoaded();
      const t = this.snapshot.adminTokens.find((x) => x.id === id);
      if (t) t.revoked = true;
      await writeJsonFileAtomic(FILE(), this.snapshot);
    });
  }

  async touchToken(id: string): Promise<void> {
    await this.queue.run(async () => {
      await this.ensureLoaded();
      const t = this.snapshot.adminTokens.find((x) => x.id === id);
      if (t) t.lastUsedAt = new Date().toISOString();
      await writeJsonFileAtomic(FILE(), this.snapshot);
    });
  }
}

declare global {
  // eslint-disable-next-line no-var
  var __settingsStore: SettingsStore | undefined;
}

export function settingsStore(): SettingsStore {
  if (!globalThis.__settingsStore) globalThis.__settingsStore = new SettingsStore();
  return globalThis.__settingsStore;
}
