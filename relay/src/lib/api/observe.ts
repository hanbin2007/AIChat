/**
 * Wraps an API route with standard observability: request ID, timing,
 * activity log entry, metrics counters. Used by every /api/v1/* route.
 */

import { newRequestId } from "@/lib/ids";
import type { AuthContext } from "@/lib/auth/bearer";
import { metrics } from "@/lib/observability/metrics";
import { compileRedactionPatterns, redactSensitive } from "@/lib/observability/redact";
import { billingStore } from "@/lib/store/billing-store";
import { settingsStore } from "@/lib/store/settings-store";
import { requestLog, type ActivityEntry, type LogCategory, type LogLevel } from "@/lib/store/request-log";

export interface ObserveContext {
  requestID: string;
  edgeRequestID?: string;
  startedAt: number;
  path: string;
  method: string;
  remoteAddress?: string;
  auth?: AuthContext;
  events: ActivityEntry["events"];
  modelID?: string;
  finishReason?: string;
  inputTokens?: number;
  outputTokens?: number;
  reservedCredits?: number;
  settledCredits?: number;
  conversationID?: string;
  requestBody?: unknown;
  responseSummary?: string;
  appVersion?: string;
  appBuild?: string;
  osVersion?: string;
  deviceModel?: string;
  locale?: string;
  idempotencyKey?: string;
}

export function beginObserve(req: Request, path: string): ObserveContext {
  const remoteAddress =
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    req.headers.get("x-real-ip") ||
    undefined;
  metrics().incCounter("relay_requests_total", 1, { path });
  return {
    requestID: newRequestId(),
    edgeRequestID: req.headers.get("x-relay-request-id") ?? undefined,
    startedAt: Date.now(),
    path,
    method: req.method,
    remoteAddress,
    events: [],
    appVersion: req.headers.get("x-aichat-app-version") ?? undefined,
    appBuild: req.headers.get("x-aichat-app-build") ?? undefined,
    osVersion: req.headers.get("x-aichat-os") ?? undefined,
    deviceModel: req.headers.get("x-aichat-device-model") ?? undefined,
    locale: req.headers.get("x-aichat-locale") ?? undefined,
    idempotencyKey: req.headers.get("idempotency-key") ?? undefined,
  };
}

/** Lightweight body summarizer for activity-log entries. Strips raw bytes. */
export function safeRequestSnapshot(body: unknown, endpoint: string): unknown {
  if (!body || typeof body !== "object") return body;
  if (endpoint.includes("/audio/transcribe")) {
    return summarizeTranscribeBody(body as Record<string, unknown>);
  }
  if (endpoint.includes("/memory/extract")) {
    return summarizeMemoryBody(body as Record<string, unknown>);
  }
  if (endpoint.includes("/chat/stream")) {
    return summarizeChatBody(body as Record<string, unknown>);
  }
  // Fallback: shallow copy + apply settings-store redaction patterns to string fields.
  return applyRedactionRules(shallowClone(body as Record<string, unknown>));
}

function shallowClone(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(input)) out[k] = v;
  return out;
}

function applyRedactionRules(obj: Record<string, unknown>): Record<string, unknown> {
  const cached = settingsStore().cachedSnapshot();
  const patterns = cached ? compileRedactionPatterns(cached.observability.redactionRules) : [];
  if (patterns.length === 0) return obj;
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    if (typeof v === "string") obj[k] = redactSensitive(v, patterns);
  }
  return obj;
}

function summarizeTranscribeBody(body: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body)) {
    if (k === "audio" || k === "audio_data" || k === "audioData") {
      out[k] = summarizeBase64Field(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

function summarizeMemoryBody(body: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body)) {
    if (k === "recentMessages" || k === "recent_messages") {
      out[k] = summarizeMessageArray(v);
    } else if (k === "archiveCandidateMessages" || k === "archive_candidate_messages") {
      out[k] = summarizeMessageArray(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

function summarizeChatBody(body: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body)) {
    if (k === "messages" && Array.isArray(v)) {
      out[k] = (v as unknown[]).map((m) => summarizeChatMessage(m));
    } else {
      out[k] = v;
    }
  }
  return out;
}

function summarizeChatMessage(m: unknown): unknown {
  if (!m || typeof m !== "object") return m;
  const src = m as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(src)) {
    if (k === "attachments" && Array.isArray(v)) {
      out[k] = (v as unknown[]).map((a) => summarizeAttachment(a));
    } else {
      out[k] = v;
    }
  }
  return out;
}

function summarizeAttachment(a: unknown): unknown {
  if (!a || typeof a !== "object") return a;
  const src = a as Record<string, unknown>;
  const mime = (src.mimeType ?? src.mime_type) as string | undefined;
  const data = (src.base64Data ?? src.base64_data) as string | undefined;
  const filename = src.filename as string | undefined;
  return {
    mimeType: mime,
    lengthBytes: typeof data === "string" ? Math.floor((data.length * 3) / 4) : 0,
    filename,
  };
}

function summarizeBase64Field(v: unknown): unknown {
  if (!v || typeof v !== "object") return v;
  const src = v as Record<string, unknown>;
  const mime = (src.mimeType ?? src.mime_type) as string | undefined;
  const data = (src.base64Data ?? src.base64_data) as string | undefined;
  const filename = src.filename as string | undefined;
  return {
    mimeType: mime,
    lengthBytes: typeof data === "string" ? Math.floor((data.length * 3) / 4) : 0,
    filename,
  };
}

function summarizeMessageArray(v: unknown): unknown {
  if (!Array.isArray(v)) return v;
  let charCount = 0;
  for (const m of v as unknown[]) {
    if (m && typeof m === "object") {
      const text = (m as Record<string, unknown>).text;
      if (typeof text === "string") charCount += text.length;
    }
  }
  return { count: v.length, charCount };
}

// ---- idempotency cache --------------------------------------------------

interface IdempotentEntry {
  key: string;
  accountID: string;
  responseBody: string;
  statusCode: number;
  storedAt: number;
}

const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000;
const IDEMPOTENCY_MAX_ENTRIES = 4096;
const idempotencyCache = new Map<string, IdempotentEntry>();

function idemKey(accountID: string, key: string): string {
  return `${accountID}::${key}`;
}

function pruneIdempotency(now: number): void {
  for (const [k, v] of idempotencyCache) {
    if (now - v.storedAt > IDEMPOTENCY_TTL_MS) idempotencyCache.delete(k);
  }
  while (idempotencyCache.size > IDEMPOTENCY_MAX_ENTRIES) {
    const oldest = idempotencyCache.keys().next().value;
    if (!oldest) break;
    idempotencyCache.delete(oldest);
  }
}

/** Look up a cached response for an `(accountID, idempotency-key)` pair. */
export function getIdempotentResponse(
  accountID: string | undefined,
  key: string | undefined,
): { responseBody: string; statusCode: number } | undefined {
  if (!accountID || !key) return undefined;
  const now = Date.now();
  pruneIdempotency(now);
  const hit = idempotencyCache.get(idemKey(accountID, key));
  if (!hit) return undefined;
  if (now - hit.storedAt > IDEMPOTENCY_TTL_MS) {
    idempotencyCache.delete(idemKey(accountID, key));
    return undefined;
  }
  return { responseBody: hit.responseBody, statusCode: hit.statusCode };
}

export function cacheIdempotentResponse(
  accountID: string | undefined,
  key: string | undefined,
  statusCode: number,
  responseBody: string,
): void {
  if (!accountID || !key) return;
  const now = Date.now();
  pruneIdempotency(now);
  idempotencyCache.set(idemKey(accountID, key), {
    accountID,
    key,
    storedAt: now,
    statusCode,
    responseBody,
  });
}

export async function finishObserve(
  ctx: ObserveContext,
  params: {
    statusCode: number;
    level: LogLevel;
    category: LogCategory;
    message: string;
    mergedAnswer?: string;
    mergedThought?: string;
  },
) {
  const elapsed = Date.now() - ctx.startedAt;
  metrics().observe("chat_latency_ms", elapsed);
  metrics().incCounter("relay_requests_done", 1, {
    path: ctx.path,
    status: String(params.statusCode),
  });
  const events = ctx.events ?? [];
  if (params.mergedAnswer !== undefined) {
    events.push({ type: "answer_delta_merged", data: { text: params.mergedAnswer }, at: new Date().toISOString() });
  }
  if (params.mergedThought !== undefined) {
    events.push({ type: "thought_delta_merged", data: { text: params.mergedThought }, at: new Date().toISOString() });
  }
  // Enrichment: look up account/device/key metadata that the schema declares.
  let accountName: string | undefined;
  let deviceAlias: string | undefined;
  let devicePlatform: string | undefined;
  let keyNote: string | undefined;
  if (ctx.auth?.clientKey) {
    try {
      const snap = await billingStore().snapshot();
      const ck = ctx.auth.clientKey;
      const acc = snap.accounts[ck.accountID];
      const dev = ck.deviceID ? snap.devices[ck.deviceID] : undefined;
      const key = snap.keys[ck.keyID];
      accountName = acc?.displayName;
      deviceAlias = dev?.alias;
      devicePlatform = dev?.platform;
      keyNote = key?.note;
    } catch {
      /* best-effort */
    }
  }
  const entry: ActivityEntry = {
    id: ctx.requestID,
    edgeRequestID: ctx.edgeRequestID,
    timestamp: new Date().toISOString(),
    level: params.level,
    category: params.category,
    message: params.message,
    method: ctx.method,
    path: ctx.path,
    remoteAddress: ctx.remoteAddress,
    statusCode: params.statusCode,
    latencyMs: elapsed,
    accountID: ctx.auth?.clientKey?.accountID,
    accountName,
    deviceID: ctx.auth?.clientKey?.deviceID,
    deviceAlias,
    devicePlatform,
    keyID: ctx.auth?.clientKey?.keyID,
    keyNote,
    modelID: ctx.modelID,
    inputTokens: ctx.inputTokens,
    outputTokens: ctx.outputTokens,
    reservedCredits: ctx.reservedCredits,
    settledCredits: ctx.settledCredits,
    finishReason: ctx.finishReason,
    conversationID: ctx.conversationID,
    requestBody: ctx.requestBody,
    responseSummary: ctx.responseSummary,
    events,
    appVersion: ctx.appVersion,
    appBuild: ctx.appBuild,
    osVersion: ctx.osVersion,
    deviceModel: ctx.deviceModel,
    locale: ctx.locale,
  };
  await requestLog().recordActivity(entry);
}
