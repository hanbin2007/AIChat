import { config } from "@/lib/config";
import { uuid } from "@/lib/ids";
import { settingsStore } from "@/lib/store/settings-store";
import { requestLog } from "@/lib/store/request-log";

export interface GenerateResponse {
  candidates?: {
    content?: { parts?: { text?: string; thought?: boolean }[] };
    finishReason?: string;
  }[];
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
  };
}

function debugEnabled(): boolean {
  const cached = settingsStore().cachedSnapshot();
  if (cached) return cached.observability.debugLoggingEnabled;
  return config.debugLogging;
}

function recordUpstreamDebug(kind: "request" | "response", title: string, body?: string, statusCode?: number): void {
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

export async function generateContent(model: string, requestBody: unknown, signal?: AbortSignal): Promise<GenerateResponse> {
  const url = `${config.geminiBaseUrl}/v1beta/models/${model}:generateContent`;
  const bodyJson = JSON.stringify(requestBody);
  recordUpstreamDebug("request", `POST ${url}`, bodyJson);
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": config.geminiApiKey,
    },
    body: bodyJson,
    signal,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    recordUpstreamDebug("response", `Gemini generateContent non-2xx`, text, res.status);
    const err = new Error(text || "Gemini generateContent failed.") as Error & { statusCode?: number };
    err.statusCode = res.status;
    throw err;
  }
  return (await res.json()) as GenerateResponse;
}

export function extractFinishReason(payload: GenerateResponse): string {
  return String(payload?.candidates?.[0]?.finishReason ?? "").trim().toUpperCase();
}

export function extractTranscript(payload: GenerateResponse): string {
  const parts = payload?.candidates?.[0]?.content?.parts ?? [];
  return parts
    .filter((p) => p.thought !== true)
    .map((p) => p.text ?? "")
    .join("\n")
    .replace(/\s+/g, " ")
    .trim();
}
