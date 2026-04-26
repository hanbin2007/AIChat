/**
 * In-memory ring buffer for request/activity/debug events + live SSE fan-out.
 * Matches Swift activity log (500) + debug log (300) defaults.
 * Recent entries are also persisted to disk so the admin UI can render
 * conversations across restarts.
 */

import path from "node:path";
import { EventEmitter } from "node:events";
import { config } from "@/lib/config";
import { conversationPins } from "./conversation-pins";
import { conversationKeyForEntry } from "./conversation-id";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "./persistence";

export type LogLevel = "info" | "success" | "warning" | "error";
export type LogCategory =
  | "lifecycle"
  | "request"
  | "completed"
  | "failure"
  | "billing"
  | "usage"
  | "system"
  | "audit";

export interface ActivityEntry {
  id: string;
  timestamp: string;
  level: LogLevel;
  category: LogCategory;
  message: string;
  method?: string;
  path?: string;
  remoteAddress?: string;
  statusCode?: number;
  latencyMs?: number;
  accountID?: string;
  accountName?: string;
  deviceID?: string;
  deviceAlias?: string;
  devicePlatform?: string;
  keyID?: string;
  keyNote?: string;
  modelID?: string;
  inputTokens?: number;
  outputTokens?: number;
  reservedCredits?: number;
  settledCredits?: number;
  finishReason?: string;
  conversationID?: string;
  requestBody?: unknown;
  responseSummary?: string;
  events?: { type: string; data: unknown; at: string }[];
}

export interface DebugEntry {
  id: string;
  timestamp: string;
  source: "client" | "relay" | "upstream";
  kind: "request" | "response" | "event";
  title: string;
  method?: string;
  path?: string;
  statusCode?: number;
  body?: string;
}

const FILE = () => path.join(config.dataDir, "request-log.json");

class RequestLog extends EventEmitter {
  private activity: ActivityEntry[] = [];
  private debug: DebugEntry[] = [];
  private activityCap = 500;
  private debugCap = 300;
  private loaded = false;
  private queue = new WriteQueue();

  async ensureLoaded() {
    if (this.loaded) return;
    const data = await readJsonFile<{ activity?: ActivityEntry[]; debug?: DebugEntry[] }>(FILE(), {});
    this.activity = data.activity ?? [];
    this.debug = data.debug ?? [];
    this.loaded = true;
  }

  configureCaps(activityCap: number, debugCap: number) {
    this.activityCap = activityCap;
    this.debugCap = debugCap;
    if (this.activity.length > activityCap) this.activity = this.activity.slice(-activityCap);
    if (this.debug.length > debugCap) this.debug = this.debug.slice(-debugCap);
  }

  async recordActivity(entry: ActivityEntry) {
    await this.ensureLoaded();
    this.activity.push(entry);
    if (this.activity.length > this.activityCap) {
      const pinned = new Set(await conversationPins().list());
      const dropAt = this.activity.findIndex(
        (e) => !pinned.has(conversationKeyForEntry(e)),
      );
      // If everything is pinned (corner case), drop the oldest anyway so the
      // ring keeps an upper bound. Otherwise drop the first non-pinned entry.
      this.activity.splice(dropAt >= 0 ? dropAt : 0, 1);
    }
    this.emit("activity", entry);
    this.schedulePersist();
  }

  async recordDebug(entry: DebugEntry) {
    await this.ensureLoaded();
    this.debug.push(entry);
    if (this.debug.length > this.debugCap) this.debug.shift();
    this.emit("debug", entry);
    this.schedulePersist();
  }

  async listActivity(): Promise<ActivityEntry[]> {
    await this.ensureLoaded();
    return [...this.activity].reverse();
  }

  async listDebug(): Promise<DebugEntry[]> {
    await this.ensureLoaded();
    return [...this.debug].reverse();
  }

  async clearActivity() {
    await this.ensureLoaded();
    this.activity = [];
    this.schedulePersist();
  }

  async clearDebug() {
    await this.ensureLoaded();
    this.debug = [];
    this.schedulePersist();
  }

  private persistScheduled = false;
  private schedulePersist() {
    if (this.persistScheduled) return;
    this.persistScheduled = true;
    // Coalesce writes; enough for an operational log.
    setTimeout(() => {
      this.persistScheduled = false;
      this.queue.run(async () => {
        await writeJsonFileAtomic(FILE(), { activity: this.activity, debug: this.debug });
      });
    }, 500);
  }
}

declare global {
  // eslint-disable-next-line no-var
  var __requestLog: RequestLog | undefined;
}

export function requestLog(): RequestLog {
  if (!globalThis.__requestLog) globalThis.__requestLog = new RequestLog();
  return globalThis.__requestLog;
}
