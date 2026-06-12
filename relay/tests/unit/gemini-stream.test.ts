import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { proxyGeminiStream } from "@/lib/gemini/stream";
import { mockGeminiStream, resetState } from "../helpers";

describe("proxyGeminiStream", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  function sse(payload: unknown): string {
    return `data: ${JSON.stringify(payload)}\n\n`;
  }

  it("re-emits answer_delta, thought_delta, done events", async () => {
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "Hi " }] } }] }),
      sse({ candidates: [{ content: { parts: [{ text: "Hi there!", thought: false }] } }] }),
      sse({ candidates: [{ content: { parts: [{ text: " Plan:", thought: true }] } }] }),
      sse({ candidates: [{ finishReason: "STOP", content: { parts: [] } }] }),
    ]);
    const events: { event: string; data: Record<string, unknown> }[] = [];
    const result = await proxyGeminiStream({
      model: "gemini-3-flash-preview",
      requestBody: {},
      onEvent: (event, data) => events.push({ event, data }),
    });

    expect(result.finishReason).toBe("STOP");
    const answers = events.filter((e) => e.event === "answer_delta").map((e) => e.data.text);
    expect(answers.join("")).toBe("Hi there!");
    const thoughts = events.filter((e) => e.event === "thought_delta").map((e) => e.data.text);
    expect(thoughts.join("")).toBe(" Plan:");
    expect(events.find((e) => e.event === "done")?.data.finishReason).toBe("STOP");
  });

  it("deduplicates cumulative chunks via normalisedDelta", async () => {
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "Hel" }] } }] }),
      sse({ candidates: [{ content: { parts: [{ text: "Hello" }] } }] }),
      sse({ candidates: [{ finishReason: "STOP", content: { parts: [] } }] }),
    ]);
    const deltas: string[] = [];
    await proxyGeminiStream({
      model: "m",
      requestBody: {},
      onEvent: (event, data) => {
        if (event === "answer_delta") deltas.push(String(data.text));
      },
    });
    expect(deltas.join("")).toBe("Hello");
  });

  it("emits attachment events once per unique image", async () => {
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: "AAA" } }] } }] }),
      sse({ candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: "AAA" } }] } }] }),
      sse({ candidates: [{ finishReason: "STOP", content: { parts: [] } }] }),
    ]);
    const attachments: unknown[] = [];
    await proxyGeminiStream({
      model: "m",
      requestBody: {},
      onEvent: (event, data) => {
        if (event === "attachment") attachments.push(data);
      },
    });
    expect(attachments).toHaveLength(1);
  });

  it("counts distinct grounded search queries from groundingMetadata", async () => {
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "ans" }] }, groundingMetadata: { webSearchQueries: ["a", "b"] } }] }),
      // Cumulative repeat + one new query — must dedupe to 3 total.
      sse({ candidates: [{ content: { parts: [] }, groundingMetadata: { webSearchQueries: ["a", "b", "c"] } }] }),
      sse({ candidates: [{ finishReason: "STOP", content: { parts: [] } }] }),
    ]);
    const result = await proxyGeminiStream({
      model: "gemini-3-flash-preview",
      requestBody: {},
      onEvent: () => undefined,
    });
    expect(result.searchQueryCount).toBe(3);
  });

  it("reports searchQueryCount 0 when no grounding metadata is present", async () => {
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "ans" }] } }] }),
      sse({ candidates: [{ finishReason: "STOP", content: { parts: [] } }] }),
    ]);
    const result = await proxyGeminiStream({
      model: "gemini-3-flash-preview",
      requestBody: {},
      onEvent: () => undefined,
    });
    expect(result.searchQueryCount).toBe(0);
  });

  it("throws on upstream non-2xx responses with the statusCode attached", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("nope", { status: 429 })),
    );
    await expect(
      proxyGeminiStream({ model: "m", requestBody: {}, onEvent: () => undefined }),
    ).rejects.toMatchObject({ statusCode: 429 });
  });

  it("emits an error event when the upstream stream never finishes", async () => {
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "partial" }] } }] }),
      // No finishReason → should trigger the terminal error event.
    ]);
    const events: string[] = [];
    await expect(
      proxyGeminiStream({
        model: "m",
        requestBody: {},
        onEvent: (event) => events.push(event),
      }),
    ).rejects.toThrow(/Incomplete/);
    expect(events).toContain("error");
  });
});
