import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { POST as transcribe } from "@/app/api/v1/audio/transcribe/route";
import { POST as memory } from "@/app/api/v1/memory/extract/route";
import { makeRequest, mockGeminiJson, resetState } from "../helpers";

describe("POST /api/v1/audio/transcribe", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("returns 401 without auth", async () => {
    const res = await transcribe(makeRequest({ url: "http://t/transcribe", method: "POST", body: {} }));
    expect(res.status).toBe(401);
  });

  it("happy path yields text + model echo", async () => {
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "hello transcript" }] } }],
      usageMetadata: { promptTokenCount: 500, candidatesTokenCount: 80, totalTokenCount: 580 },
    });
    const res = await transcribe(
      makeRequest({
        url: "http://t/transcribe",
        method: "POST",
        headers: { Authorization: "Bearer test-bearer-token" },
        body: { audio: { mimeType: "audio/m4a", base64Data: "AAA" } },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { text: string; model: string };
    expect(body.text).toBe("hello transcript");
    expect(body.model).toBe("gemini-3-flash-preview");
  });

  it("maps MAX_TOKENS to a 502 error", async () => {
    mockGeminiJson({
      candidates: [{ finishReason: "MAX_TOKENS", content: { parts: [{ text: "…" }] } }],
    });
    const res = await transcribe(
      makeRequest({
        url: "http://t/transcribe",
        method: "POST",
        headers: { Authorization: "Bearer test-bearer-token" },
        body: { audio: { mimeType: "audio/m4a", base64Data: "AAA" } },
      }),
    );
    expect(res.status).toBe(502);
  });
});

describe("POST /api/v1/memory/extract", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("parses a JSON memory schema response", async () => {
    const schema = {
      kind: "casual",
      title: "Hello",
      focusNote: "note",
      openLoops: ["check in"],
      memoryItems: ["fact"],
      archiveTitle: null,
      archiveSummary: null,
      archiveOpenLoops: [],
    };
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: JSON.stringify(schema) }] } }],
    });
    const res = await memory(
      makeRequest({
        url: "http://t/memory",
        method: "POST",
        headers: { Authorization: "Bearer test-bearer-token" },
        body: { mode: "casual", recentMessages: [{ role: "user", text: "hi" }] },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as typeof schema;
    expect(body.title).toBe("Hello");
    expect(body.memoryItems).toEqual(["fact"]);
  });

  it("tolerates markdown-wrapped JSON by extracting the object", async () => {
    const schema = {
      kind: "task",
      title: "t",
      focusNote: "",
      openLoops: [],
      memoryItems: [],
      archiveTitle: null,
      archiveSummary: null,
      archiveOpenLoops: [],
    };
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "```json\n" + JSON.stringify(schema) + "\n```" }] } }],
    });
    const res = await memory(
      makeRequest({
        url: "http://t/memory",
        method: "POST",
        headers: { Authorization: "Bearer test-bearer-token" },
        body: { mode: "task" },
      }),
    );
    expect(res.status).toBe(200);
  });

  it("returns 502 when Gemini returns non-JSON garbage", async () => {
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "definitely not json" }] } }],
    });
    const res = await memory(
      makeRequest({
        url: "http://t/memory",
        method: "POST",
        headers: { Authorization: "Bearer test-bearer-token" },
        body: { mode: "casual" },
      }),
    );
    expect(res.status).toBe(502);
  });
});
