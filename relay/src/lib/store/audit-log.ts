/**
 * Append-only audit log with HMAC chain — each entry carries the SHA-256
 * HMAC of the previous entry so tampering is detectable. Matches v0.3 §2.6.
 */

import path from "node:path";
import { createHmac } from "node:crypto";
import { config } from "@/lib/config";
import { uuid } from "@/lib/ids";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "./persistence";

export interface AuditEntry {
  id: string;
  timestamp: string;
  actor: string;
  role: string;
  action: string;
  target?: string;
  before?: unknown;
  after?: unknown;
  details?: unknown;
  ip?: string;
  prevHash: string;
  hash: string;
}

const FILE = () => path.join(config.dataDir, "audit.json");
const REDACTED = "[redacted]";

function shouldRedactField(key: string): boolean {
  const normalized = key.toLowerCase();
  return normalized.includes("token") || normalized.includes("key") || normalized.includes("password");
}

export function sanitizeAuditPayload<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeAuditPayload(item)) as T;
  }
  if (!value || typeof value !== "object") return value;

  const output: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (key === "adminTokens" && Array.isArray(item)) {
      output[key] = item.map((token) => {
        if (!token || typeof token !== "object" || Array.isArray(token)) return sanitizeAuditPayload(token);
        return { ...sanitizeAuditPayload(token), value: REDACTED };
      });
    } else if (key === "value" && "prefix" in (value as Record<string, unknown>) && "scope" in (value as Record<string, unknown>)) {
      output[key] = REDACTED;
    } else if (shouldRedactField(key)) {
      output[key] = REDACTED;
    } else {
      output[key] = sanitizeAuditPayload(item);
    }
  }
  return output as T;
}

class AuditLog {
  private entries: AuditEntry[] = [];
  private loaded = false;
  private queue = new WriteQueue();

  async ensureLoaded() {
    if (this.loaded) return;
    this.entries = await readJsonFile<AuditEntry[]>(FILE(), []);
    this.loaded = true;
  }

  async append(input: Omit<AuditEntry, "id" | "timestamp" | "prevHash" | "hash">): Promise<AuditEntry> {
    return this.queue.run(async () => {
      await this.ensureLoaded();
      const prev = this.entries[this.entries.length - 1];
      const prevHash = prev ? prev.hash : "GENESIS";
      const entry: AuditEntry = {
        ...sanitizeAuditPayload(input),
        id: uuid(),
        timestamp: new Date().toISOString(),
        prevHash,
        hash: "",
      };
      const mac = createHmac("sha256", config.sessionSecret || "relay-audit");
      mac.update(JSON.stringify({ ...entry, hash: undefined }));
      entry.hash = mac.digest("base64url");
      this.entries.push(entry);
      await writeJsonFileAtomic(FILE(), this.entries);
      return entry;
    });
  }

  async list(limit = 200): Promise<AuditEntry[]> {
    await this.ensureLoaded();
    return this.entries.slice(-limit).reverse().map((entry) => sanitizeAuditPayload(entry));
  }
}

declare global {
  // eslint-disable-next-line no-var
  var __auditLog: AuditLog | undefined;
}

export function auditLog(): AuditLog {
  if (!globalThis.__auditLog) globalThis.__auditLog = new AuditLog();
  return globalThis.__auditLog;
}
