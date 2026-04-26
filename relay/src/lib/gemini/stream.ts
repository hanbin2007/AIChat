/**
 * Proxy a Gemini streamGenerateContent SSE response and re-emit it as
 * `answer_delta` / `thought_delta` / `model_content` / `attachment` / `done` /
 * `error` events, identical to the macOS AIChat Relay.
 *
 * The delta dedup logic matches `normalizedDelta` in the Swift bridge: some
 * Gemini chunks return cumulative text, others incremental. We track the last
 * emitted buffer and only forward the genuine diff.
 */

import { config } from "@/lib/config";
import { uuid } from "@/lib/ids";
import { settingsStore } from "@/lib/store/settings-store";
import { requestLog } from "@/lib/store/request-log";

function debugEnabled(): boolean {
  const cached = settingsStore().cachedSnapshot();
  if (cached) return cached.observability.debugLoggingEnabled;
  return config.debugLogging;
}

function recordUpstreamDebug(kind: "request" | "response" | "event", title: string, body?: string, statusCode?: number): void {
  if (!debugEnabled()) return;
  requestLog()
    .recordDebug({
      id: uuid(),
      timestamp: new Date().toISOString(),
      source: "upstream",
      kind,
      title,
      statusCode,
      body,
    })
    .catch(() => undefined);
}

interface GeminiPart {
  text?: string;
  thought?: boolean;
  inlineData?: { mimeType?: string; data?: string };
}

interface ChunkSummary {
  answerText: string;
  thoughtText: string;
  attachments: { mimeType: string; base64Data: string; filename: string }[];
  finishReason: string;
  rawParts: GeminiPart[];
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number; totalTokenCount?: number };
}

function summariseChunk(chunk: unknown): ChunkSummary {
  const c = chunk as {
    candidates?: { content?: { parts?: GeminiPart[] }; finishReason?: string }[];
    usageMetadata?: ChunkSummary["usageMetadata"];
  };
  const candidate = c.candidates?.[0];
  const parts = candidate?.content?.parts ?? [];
  const answerText = parts.filter((p) => p.thought !== true).map((p) => p.text ?? "").join("");
  const thoughtText = parts.filter((p) => p.thought === true).map((p) => p.text ?? "").join("");
  const attachments = parts
    .filter((p) => String(p.inlineData?.mimeType ?? "").toLowerCase().startsWith("image/"))
    .map((p) => ({
      mimeType: p.inlineData?.mimeType ?? "",
      base64Data: p.inlineData?.data ?? "",
      filename: "generated-image",
    }));
  return {
    answerText,
    thoughtText,
    attachments,
    finishReason: typeof candidate?.finishReason === "string" ? candidate.finishReason.trim() : "",
    rawParts: parts,
    usageMetadata: c.usageMetadata,
  };
}

function normalisedDelta(next: string, emitted: string): { delta: string; emitted: string } {
  if (!next) return { delta: "", emitted };
  if (next.startsWith(emitted)) return { delta: next.slice(emitted.length), emitted: next };
  if (emitted.startsWith(next)) return { delta: "", emitted };
  return { delta: next, emitted: emitted + next };
}

export interface StreamResult {
  finishReason: string;
  answerText: string;
  thoughtText: string;
  modelContentParts: GeminiPart[];
  usage?: { promptTokens: number; candidatesTokens: number; totalTokens: number };
  /** True when `usage` was estimated locally because Gemini did not emit
   * `usageMetadata` on any chunk. Routes can pass this through to settle so
   * operators can see the discrepancy. */
  usageEstimated?: boolean;
}

export async function proxyGeminiStream(params: {
  model: string;
  requestBody: unknown;
  onEvent: (event: string, data: Record<string, unknown>) => void;
  /** Aborts the upstream fetch when the originating client disconnects. */
  signal?: AbortSignal;
  /** Client-supplied input token estimate, used only as a fallback when
   * Gemini omits `usageMetadata`. */
  estimatedInputTokens?: number;
}): Promise<StreamResult> {
  const url = `${config.geminiBaseUrl}/v1beta/models/${params.model}:streamGenerateContent?alt=sse`;
  const requestBodyJson = JSON.stringify(params.requestBody);
  recordUpstreamDebug("request", `POST ${url}`, requestBodyJson);
  const upstream = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "text/event-stream",
      "x-goog-api-key": config.geminiApiKey,
    },
    body: requestBodyJson,
    signal: params.signal,
  });

  if (!upstream.ok || !upstream.body) {
    const text = await upstream.text().catch(() => "");
    recordUpstreamDebug("response", `Gemini stream non-2xx`, text, upstream.status);
    const err = new Error(text || "Gemini stream failed.") as Error & { statusCode?: number };
    err.statusCode = upstream.status;
    throw err;
  }

  const decoder = new TextDecoder();
  const reader = upstream.body.getReader();
  let buffered = "";
  let emittedAnswer = "";
  let emittedThought = "";
  const emittedAttachmentKeys = new Set<string>();
  let finishReason = "";
  const accumulatedParts: GeminiPart[] = [];
  let lastUsage: ChunkSummary["usageMetadata"];
  let chunksSeen = 0;
  // Multi-line SSE continuation buffer. Per the SSE spec, consecutive `data:`
  // lines within a single event (terminated by a blank line) concatenate with
  // a literal newline between them.
  let pendingDataLines: string[] = [];

  const flushEvent = () => {
    if (pendingDataLines.length === 0) return;
    const payload = pendingDataLines.join("\n").trim();
    pendingDataLines = [];
    if (!payload || payload === "[DONE]") return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(payload);
    } catch {
      return;
    }
    chunksSeen += 1;
    const summary = summariseChunk(parsed);
    if (summary.finishReason) finishReason = summary.finishReason;
    if (summary.usageMetadata) lastUsage = summary.usageMetadata;
    accumulatedParts.push(...summary.rawParts);

    for (const attachment of summary.attachments) {
      const key = `${attachment.mimeType.toLowerCase()}|${attachment.base64Data}`;
      if (emittedAttachmentKeys.has(key)) continue;
      emittedAttachmentKeys.add(key);
      params.onEvent("attachment", { type: "attachment", attachment });
    }

    if (summary.thoughtText) {
      const r = normalisedDelta(summary.thoughtText, emittedThought);
      emittedThought = r.emitted;
      if (r.delta) params.onEvent("thought_delta", { type: "thought_delta", text: r.delta });
    }
    if (summary.answerText) {
      const r = normalisedDelta(summary.answerText, emittedAnswer);
      emittedAnswer = r.emitted;
      if (r.delta) params.onEvent("answer_delta", { type: "answer_delta", text: r.delta });
    }
    // Forward raw parts for thought signatures etc. (Watch reconstructs
    // modelResponseParts from these so multi-turn context stays intact.)
    if (summary.rawParts.length) {
      params.onEvent("model_content", { type: "model_content", parts: summary.rawParts });
    }
  };

  const ingestLine = (raw: string) => {
    // Per SSE spec: blank line terminates the current event.
    if (raw === "" || raw === "\r") {
      flushEvent();
      return;
    }
    // Comment lines start with ":" — discard.
    if (raw.startsWith(":")) return;
    if (raw.startsWith("data:")) {
      // Drop a single optional leading space after the colon.
      const value = raw.slice(5).startsWith(" ") ? raw.slice(6) : raw.slice(5);
      pendingDataLines.push(value);
      return;
    }
    // Other field types (event:, id:, retry:) are unused upstream; ignore.
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffered += decoder.decode(value, { stream: true });
    const lines = buffered.split("\n");
    buffered = lines.pop() ?? "";
    for (const line of lines) ingestLine(line.replace(/\r$/, ""));
  }
  buffered += decoder.decode();
  if (buffered) ingestLine(buffered.replace(/\r$/, ""));
  // Final flush in case the stream ended without a trailing blank line.
  flushEvent();

  if (!finishReason) {
    params.onEvent("error", {
      type: "error",
      message: "Relay stream ended before Gemini sent a terminal chunk.",
    });
    throw new Error("Incomplete upstream stream.");
  }

  params.onEvent("done", { type: "done", finishReason });

  // Build a usage object. If Gemini never sent `usageMetadata` (some preview
  // models, or a stream that hits finishReason on a chunk without usage), we
  // estimate from character counts so settle won't fall back to charging the
  // floor of 1 credit on a real chat.
  let usage: StreamResult["usage"];
  let usageEstimated = false;
  if (lastUsage) {
    usage = {
      promptTokens: lastUsage.promptTokenCount ?? 0,
      candidatesTokens: lastUsage.candidatesTokenCount ?? 0,
      totalTokens: lastUsage.totalTokenCount ?? 0,
    };
  } else {
    const estOutput = Math.max(0, Math.ceil((emittedAnswer.length + emittedThought.length) / 4));
    const estInput =
      typeof params.estimatedInputTokens === "number" && params.estimatedInputTokens > 0
        ? params.estimatedInputTokens
        : 0;
    // Structured warning so operators can spot models that drop usage.
    console.warn(
      JSON.stringify({
        msg: "gemini.stream.usage_missing",
        model: params.model,
        chunksSeen,
        finishReason,
        estInput,
        estOutput,
      }),
    );
    usage = { promptTokens: estInput, candidatesTokens: estOutput, totalTokens: estInput + estOutput };
    usageEstimated = true;
  }

  return {
    finishReason,
    answerText: emittedAnswer,
    thoughtText: emittedThought,
    modelContentParts: accumulatedParts,
    usage,
    usageEstimated,
  };
}
