import { promises as fs } from "node:fs";
import { vi } from "vitest";
import { config } from "@/lib/config";

type GlobalStores = {
  __billingStore?: unknown;
  __settingsStore?: unknown;
  __requestLog?: unknown;
  __auditLog?: unknown;
  __metrics?: unknown;
  __rateLimiter?: unknown;
  __cookieJar?: Map<string, string>;
};

/** Wipe on-disk state + in-memory singletons so each test starts fresh. */
export async function resetState(): Promise<void> {
  const g = globalThis as GlobalStores;
  delete g.__billingStore;
  delete g.__settingsStore;
  delete g.__requestLog;
  delete g.__auditLog;
  delete g.__metrics;
  delete g.__rateLimiter;
  g.__cookieJar?.clear();
  try {
    const entries = await fs.readdir(config.dataDir);
    for (const name of entries) {
      if (name.startsWith(".")) continue;
      await fs.rm(`${config.dataDir}/${name}`, { recursive: true, force: true });
    }
  } catch {
    /* dataDir doesn't exist yet */
  }
}

export function cookieJar(): Map<string, string> {
  return (globalThis as GlobalStores).__cookieJar!;
}

/** Build a Request for a Next.js route handler. */
export function makeRequest(init: {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: unknown;
}): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json", ...(init.headers ?? {}) };
  return new Request(init.url, {
    method: init.method ?? "GET",
    headers,
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
}

/** Mock global fetch to return a ready-made SSE ReadableStream. */
export function mockGeminiStream(chunks: string[]): void {
  const encoder = new TextEncoder();
  const body = new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
      controller.close();
    },
  });
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => new Response(body, {
      status: 200,
      headers: { "Content-Type": "text/event-stream" },
    })),
  );
}

/** Mock global fetch to return a non-streaming JSON payload. */
export function mockGeminiJson(payload: unknown, status = 200): void {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => new Response(JSON.stringify(payload), {
      status,
      headers: { "Content-Type": "application/json" },
    })),
  );
}

/** Build a base64url JWS-shaped string that decodes to `payload`. Signature
 * is left empty — we only exercise decoding, never verification. */
export function forgeJws(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: "ES256", typ: "JWT" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${header}.${body}.sig`;
}

/** Collect all SSE events from a Response.body. */
export async function readSseEvents(response: Response): Promise<{ event: string; data: string }[]> {
  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  const events: { event: string; data: string }[] = [];
  let buffered = "";
  let currentEvent = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffered += decoder.decode(value, { stream: true });
    const lines = buffered.split("\n");
    buffered = lines.pop() ?? "";
    for (const line of lines) {
      if (line.startsWith("event:")) currentEvent = line.slice(6).trim();
      else if (line.startsWith("data:")) events.push({ event: currentEvent, data: line.slice(5).trim() });
    }
  }
  return events;
}

/** Iterate in tiny async chunks to let IO queue drain. */
export async function flush(): Promise<void> {
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
}
