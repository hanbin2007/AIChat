/**
 * Wraps an API route with standard observability: request ID, timing,
 * activity log entry, metrics counters. Used by every /api/v1/* route.
 */

import { newRequestId } from "@/lib/ids";
import type { AuthContext } from "@/lib/auth/bearer";
import { metrics } from "@/lib/observability/metrics";
import { requestLog, type ActivityEntry, type LogCategory, type LogLevel } from "@/lib/store/request-log";

export interface ObserveContext {
  requestID: string;
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
}

export function beginObserve(req: Request, path: string): ObserveContext {
  const remoteAddress =
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    req.headers.get("x-real-ip") ||
    undefined;
  metrics().incCounter("relay_requests_total", 1, { path });
  return {
    requestID: newRequestId(),
    startedAt: Date.now(),
    path,
    method: req.method,
    remoteAddress,
    events: [],
  };
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
  const entry: ActivityEntry = {
    id: ctx.requestID,
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
    deviceID: ctx.auth?.clientKey?.deviceID,
    keyID: ctx.auth?.clientKey?.keyID,
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
  };
  await requestLog().recordActivity(entry);
}
