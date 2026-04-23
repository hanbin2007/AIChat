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
}

export async function proxyGeminiStream(params: {
  model: string;
  requestBody: unknown;
  onEvent: (event: string, data: Record<string, unknown>) => void;
}): Promise<StreamResult> {
  const url = `${config.geminiBaseUrl}/v1beta/models/${params.model}:streamGenerateContent?alt=sse`;
  const upstream = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "text/event-stream",
      "x-goog-api-key": config.geminiApiKey,
    },
    body: JSON.stringify(params.requestBody),
  });

  if (!upstream.ok || !upstream.body) {
    const text = await upstream.text().catch(() => "");
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

  const ingest = (raw: string) => {
    const trimmed = raw.trim();
    if (!trimmed.startsWith("data:")) return;
    const payload = trimmed.slice(5).trim();
    if (!payload || payload === "[DONE]") return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(payload);
    } catch {
      return;
    }
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

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffered += decoder.decode(value, { stream: true });
    const lines = buffered.split("\n");
    buffered = lines.pop() ?? "";
    for (const line of lines) ingest(line);
  }
  buffered += decoder.decode();
  if (buffered.trim()) ingest(buffered);

  if (!finishReason) {
    params.onEvent("error", {
      type: "error",
      message: "Relay stream ended before Gemini sent a terminal chunk.",
    });
    throw new Error("Incomplete upstream stream.");
  }

  params.onEvent("done", { type: "done", finishReason });

  return {
    finishReason,
    answerText: emittedAnswer,
    thoughtText: emittedThought,
    modelContentParts: accumulatedParts,
    usage: lastUsage
      ? {
          promptTokens: lastUsage.promptTokenCount ?? 0,
          candidatesTokens: lastUsage.candidatesTokenCount ?? 0,
          totalTokens: lastUsage.totalTokenCount ?? 0,
        }
      : undefined,
  };
}
