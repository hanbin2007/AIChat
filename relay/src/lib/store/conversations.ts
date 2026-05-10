/**
 * Rebuild "conversations" from the request log. A conversation is identified
 * by the `x-aichat-conversation-id` header when present, else by the SHA-1
 * of `device + first user message`.
 *
 * Messages inside each turn are reconstructed from the original request body
 * (messages[] array) and, for the final assistant turn, from the merged
 * SSE deltas captured during proxying.
 */

import { createHash } from "node:crypto";
import { requestLog, type ActivityEntry } from "./request-log";

export interface ConversationTurn {
  id: string;
  timestamp: string;
  requestID: string;
  userText?: string;
  assistantText?: string;
  thoughtText?: string;
  attachments?: { mimeType: string; base64Data: string; filename?: string }[];
  modelID?: string;
  thinkingIntensity?: string;
  inputTokens?: number;
  outputTokens?: number;
  credits?: number;
  latencyMs?: number;
  finishReason?: string;
  error?: string;
  confidence: "high" | "low";
}

export interface Conversation {
  id: string;
  confidence: "high" | "low";
  title: string;
  accountID?: string;
  accountName?: string;
  deviceID?: string;
  deviceAlias?: string;
  devicePlatform?: string;
  firstAt: string;
  lastAt: string;
  turnCount: number;
  modelsUsed: string[];
  totalInputTokens: number;
  totalOutputTokens: number;
  totalCredits: number;
  turns: ConversationTurn[];
  hasErrors: boolean;
  hasImages: boolean;
  hasAudio: boolean;
}

function firstLine(text: string | undefined, max = 60): string {
  if (!text) return "Untitled";
  const line = text.trim().split(/\r?\n/)[0] ?? "";
  if (line.length <= max) return line;
  return `${line.slice(0, max - 1)}…`;
}

// The watch sends the full history every turn; the new user input for this
// turn is the LAST user message in messages[], not the first.
function messagePreview(messages: Record<string, unknown>[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if ((m?.role ?? "user") === "user" && typeof m?.text === "string") return m.text;
  }
  const fallback = messages[0];
  return typeof fallback?.text === "string" ? fallback.text : "";
}

// Auto-key fingerprints by (deviceID, first user message) — the only piece of
// the request body stable across every turn. Slicing the cumulative history
// (e.g. first 3 messages) shatters one real conversation across multiple
// buckets as it grows.
function conversationKey(entry: ActivityEntry): string {
  if (entry.conversationID) return entry.conversationID;
  const body = (entry.requestBody as Record<string, unknown> | undefined) ?? {};
  const messages = Array.isArray(body.messages) ? (body.messages as Record<string, unknown>[]) : [];
  const firstUser = messages.find((m) => (m?.role ?? "user") === "user") as
    | Record<string, unknown>
    | undefined;
  const seed = typeof firstUser?.text === "string" ? firstUser.text : "";
  const h = createHash("sha1").update(`${entry.deviceID ?? ""}|${seed}`).digest("hex");
  return `auto-${h.slice(0, 16)}`;
}

export async function listConversations(opts: {
  limit?: number;
  accountID?: string;
  deviceID?: string;
  modelID?: string;
  hasErrors?: boolean;
  hasImages?: boolean;
  hasAudio?: boolean;
  query?: string;
} = {}): Promise<Conversation[]> {
  const entries = (await requestLog().listActivity())
    .filter((e) => e.path === "/api/v1/chat/stream" || e.path === "/api/v1/audio/transcribe")
    .reverse();

  const byKey = new Map<string, Conversation>();
  for (const entry of entries) {
    const key = conversationKey(entry);
    const confidence = entry.conversationID ? "high" : "low";
    const body = (entry.requestBody as Record<string, unknown> | undefined) ?? {};
    const messages = Array.isArray(body.messages) ? (body.messages as Record<string, unknown>[]) : [];
    const userText = messagePreview(messages);
    const answerEvent = entry.events?.find((e) => e.type === "answer_delta_merged");
    const thoughtEvent = entry.events?.find((e) => e.type === "thought_delta_merged");
    const assistantText = answerEvent ? String((answerEvent.data as { text?: string }).text ?? "") : "";
    const thoughtText = thoughtEvent ? String((thoughtEvent.data as { text?: string }).text ?? "") : "";

    const turn: ConversationTurn = {
      id: entry.id,
      timestamp: entry.timestamp,
      requestID: entry.id,
      userText,
      assistantText,
      thoughtText: thoughtText || undefined,
      modelID: entry.modelID,
      thinkingIntensity: typeof body.thinkingIntensity === "string" ? (body.thinkingIntensity as string) : undefined,
      inputTokens: entry.inputTokens,
      outputTokens: entry.outputTokens,
      credits: entry.settledCredits ?? entry.reservedCredits,
      latencyMs: entry.latencyMs,
      finishReason: entry.finishReason,
      error: entry.level === "error" ? entry.message : undefined,
      confidence,
    };

    const existing = byKey.get(key);
    const first = existing?.firstAt ?? entry.timestamp;
    const models = new Set(existing?.modelsUsed ?? []);
    if (entry.modelID) models.add(entry.modelID);
    const hasImages = messages.some((m) => {
      const atts = Array.isArray(m.attachments) ? (m.attachments as { mimeType?: string }[]) : [];
      return atts.some((a) => String(a.mimeType ?? "").toLowerCase().startsWith("image/"));
    });
    const hasAudio = entry.path === "/api/v1/audio/transcribe" || messages.some((m) => {
      const atts = Array.isArray(m.attachments) ? (m.attachments as { mimeType?: string }[]) : [];
      return atts.some((a) => String(a.mimeType ?? "").toLowerCase().startsWith("audio/"));
    });

    const next: Conversation = {
      id: key,
      confidence,
      title: existing?.title ?? firstLine(userText),
      accountID: entry.accountID,
      accountName: entry.accountName,
      deviceID: entry.deviceID,
      deviceAlias: entry.deviceAlias,
      devicePlatform: entry.devicePlatform,
      firstAt: first,
      lastAt: entry.timestamp,
      turnCount: (existing?.turnCount ?? 0) + 1,
      modelsUsed: Array.from(models),
      totalInputTokens: (existing?.totalInputTokens ?? 0) + (entry.inputTokens ?? 0),
      totalOutputTokens: (existing?.totalOutputTokens ?? 0) + (entry.outputTokens ?? 0),
      totalCredits: (existing?.totalCredits ?? 0) + (entry.settledCredits ?? entry.reservedCredits ?? 0),
      turns: [...(existing?.turns ?? []), turn],
      hasErrors: (existing?.hasErrors ?? false) || entry.level === "error",
      hasImages: (existing?.hasImages ?? false) || hasImages,
      hasAudio: (existing?.hasAudio ?? false) || hasAudio,
    };
    byKey.set(key, next);
  }

  for (const conv of byKey.values()) {
    conv.turns.sort((a, b) => (a.timestamp < b.timestamp ? -1 : a.timestamp > b.timestamp ? 1 : 0));
    conv.firstAt = conv.turns[0]?.timestamp ?? conv.firstAt;
    conv.lastAt = conv.turns[conv.turns.length - 1]?.timestamp ?? conv.lastAt;
    // Title reflects the chronologically-first turn, even if records arrived
    // out of order.
    conv.title = firstLine(conv.turns[0]?.userText);
  }
  let list = Array.from(byKey.values()).sort((a, b) => (a.lastAt < b.lastAt ? 1 : -1));

  if (opts.accountID) list = list.filter((c) => c.accountID === opts.accountID);
  if (opts.deviceID) list = list.filter((c) => c.deviceID === opts.deviceID);
  if (opts.modelID) list = list.filter((c) => c.modelsUsed.includes(opts.modelID!));
  if (opts.hasErrors) list = list.filter((c) => c.hasErrors);
  if (opts.hasImages) list = list.filter((c) => c.hasImages);
  if (opts.hasAudio) list = list.filter((c) => c.hasAudio);
  if (opts.query) {
    const q = opts.query.toLowerCase();
    list = list.filter((c) =>
      c.title.toLowerCase().includes(q) ||
      c.turns.some((t) => (t.userText ?? "").toLowerCase().includes(q) || (t.assistantText ?? "").toLowerCase().includes(q)),
    );
  }
  if (opts.limit) list = list.slice(0, opts.limit);
  return list;
}

export async function getConversation(id: string): Promise<Conversation | null> {
  const list = await listConversations({ limit: 9999 });
  return list.find((c) => c.id === id) ?? null;
}
