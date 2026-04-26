import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { POST as chat } from "@/app/api/v1/chat/stream/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { billingStore } from "@/lib/store/billing-store";
import { makeRequest, resetState } from "../helpers";

function sse(payload: unknown): string {
  return `data: ${JSON.stringify(payload)}\n\n`;
}

/**
 * Mock Gemini with a paced stream: emits one chunk, then awaits a long tail.
 * This gives the test time to abort the request while the proxy is mid-stream.
 */
function mockSlowGeminiStream() {
  const encoder = new TextEncoder();
  let tail: ReadableStreamDefaultController<Uint8Array> | null = null;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(sse({ candidates: [{ content: { parts: [{ text: "Hi" }] } }] })));
      tail = controller;
    },
  });
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => new Response(body, { status: 200, headers: { "Content-Type": "text/event-stream" } })),
  );
  return () => tail?.close();
}

describe("chat/stream client-disconnect handling", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("rolls back the credit reservation when the request signal aborts", async () => {
    const boot = await (
      await bootstrap(
        makeRequest({
          url: "http://t/bootstrap",
          method: "POST",
          body: { deviceID: "d1", platform: "watch" },
        }),
      )
    ).json();

    const releaseTail = mockSlowGeminiStream();

    const abort = new AbortController();
    const req = new Request("http://t/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${boot.key.keyValue}`,
      },
      body: JSON.stringify({ messages: [{ role: "user", text: "hi" }] }),
      signal: abort.signal,
    });
    const res = await chat(req);
    expect(res.status).toBe(200);
    // Start reading so the stream body is hot, then abort.
    const reader = res.body!.getReader();
    await reader.read();
    abort.abort();
    releaseTail();
    // Give the abort listener a tick to run.
    await new Promise((r) => setTimeout(r, 50));

    const snap = await billingStore().snapshot();
    expect(snap.accounts[boot.account.accountID].creditBalance).toBe(800);
  });
});
