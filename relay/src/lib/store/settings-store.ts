/**
 * Operator-editable runtime settings. Persisted alongside billing state so a
 * single volume backup captures the whole relay.
 */

import path from "node:path";
import { config } from "@/lib/config";
import { hashPassword, verifyPassword } from "@/lib/auth/password";
import { newBearerToken, uuid } from "@/lib/ids";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "./persistence";

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
  value: string;
  scope: "admin" | "client";
  rpmLimit?: number;
  concurrentStreams?: number;
  allowedEndpoints?: string[];
  ipAllowlist?: string[];
  expiresAt?: string;
  createdAt: string;
  lastUsedAt?: string;
  revoked?: boolean;
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
      mode: config.billingMode,
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

class SettingsStore {
  private snapshot: SettingsSnapshot = emptySnapshot();
  private loaded = false;
  private queue = new WriteQueue();

  async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    const persisted = await readJsonFile<Partial<SettingsSnapshot>>(FILE(), {});
    this.snapshot = { ...emptySnapshot(), ...persisted } as SettingsSnapshot;
    this.loaded = true;
  }

  async get(): Promise<SettingsSnapshot> {
    await this.ensureLoaded();
    return JSON.parse(JSON.stringify(this.snapshot));
  }

  async update(patch: Partial<SettingsSnapshot>): Promise<void> {
    await this.queue.run(async () => {
      await this.ensureLoaded();
      this.snapshot = { ...this.snapshot, ...patch } as SettingsSnapshot;
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

  async issueToken(params: Omit<AdminToken, "id" | "value" | "prefix" | "createdAt">): Promise<AdminToken> {
    return this.queue.run(async () => {
      await this.ensureLoaded();
      const value = newBearerToken();
      const token: AdminToken = {
        ...params,
        id: uuid(),
        value,
        prefix: value.slice(0, 8),
        createdAt: new Date().toISOString(),
      };
      this.snapshot.adminTokens.push(token);
      await writeJsonFileAtomic(FILE(), this.snapshot);
      return token;
    });
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
