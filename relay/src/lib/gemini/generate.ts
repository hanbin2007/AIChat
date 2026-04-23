import { config } from "@/lib/config";

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

export async function generateContent(model: string, requestBody: unknown): Promise<GenerateResponse> {
  const res = await fetch(`${config.geminiBaseUrl}/v1beta/models/${model}:generateContent`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": config.geminiApiKey,
    },
    body: JSON.stringify(requestBody),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
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
