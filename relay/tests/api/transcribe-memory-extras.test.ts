import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { POST as transcribe } from "@/app/api/v1/audio/transcribe/route";
import { POST as memory } from "@/app/api/v1/memory/extract/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { billingStore } from "@/lib/store/billing-store";
import { makeRequest, mockGeminiJson, resetState } from "../helpers";

async function bootstrapKey(deviceID: string) {
  const res = await bootstrap(
    makeRequest({
      url: "http://test/api/v1/activation/bootstrap",
      method: "POST",
      body: { deviceID, platform: "watch" },
    }),
  );
  const body = (await res.json()) as {
    account: { accountID: string };
    key: { keyValue: string };
  };
  return body;
}

describe("transcribe additional coverage", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("returns 400 for malformed JSON body (with auth)", async () => {
    const req = new Request("http://t/transcribe", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer test-bearer-token",
      },
      body: "{ not json",
    });
    const res = await transcribe(req);
    expect(res.status).toBe(400);
  });

  it("reserves and settles credits when called with a client key", async () => {
    const boot = await bootstrapKey("watch-tx-1");
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "transcribed text" }] } }],
      usageMetadata: { promptTokenCount: 200, candidatesTokenCount: 30, totalTokenCount: 230 },
    });
    const res = await transcribe(
      makeRequest({
        url: "http://t/transcribe",
        method: "POST",
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        body: {
          audio: { mimeType: "audio/m4a", base64Data: "AAA" },
          model: "gemini-3-flash-preview",
        },
      }),
    );
    expect(res.status).toBe(200);
    const snap = await billingStore().snapshot();
    const records = snap.usage.filter((u) => u.accountID === boot.account.accountID);
    expect(records).toHaveLength(1);
    expect(records[0].settledCredits).toBeGreaterThan(0);
  });

  it("rolls back the reservation when Gemini returns no usable transcript", async () => {
    const boot = await bootstrapKey("watch-tx-2");
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "" }] } }],
    });
    const before = await billingStore().snapshot();
    const beforeBalance = before.accounts[boot.account.accountID].creditBalance;
    const res = await transcribe(
      makeRequest({
        url: "http://t/transcribe",
        method: "POST",
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        body: { audio: { mimeType: "audio/m4a", base64Data: "AAA" } },
      }),
    );
    expect(res.status).toBe(502);
    const after = await billingStore().snapshot();
    expect(after.accounts[boot.account.accountID].creditBalance).toBe(beforeBalance);
  });

  it("returns 502 when Gemini returns no terminal finishReason", async () => {
    mockGeminiJson({
      candidates: [{ content: { parts: [{ text: "partial" }] } }],
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

  it("returns 502 when Gemini reports an unexpected finishReason", async () => {
    mockGeminiJson({
      candidates: [{ finishReason: "SAFETY", content: { parts: [{ text: "x" }] } }],
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

describe("memory additional coverage", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("returns 401 without auth", async () => {
    const res = await memory(
      makeRequest({ url: "http://t/memory", method: "POST", body: { mode: "casual" } }),
    );
    expect(res.status).toBe(401);
  });

  it("returns 400 for malformed JSON body (with auth)", async () => {
    const req = new Request("http://t/memory", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer test-bearer-token",
      },
      body: "garbage{",
    });
    const res = await memory(req);
    expect(res.status).toBe(400);
  });

  it("returns 502 when Gemini reports MAX_TOKENS", async () => {
    mockGeminiJson({
      candidates: [{ finishReason: "MAX_TOKENS", content: { parts: [{ text: "{}" }] } }],
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

  it("returns 502 when Gemini lacks a terminal finishReason", async () => {
    mockGeminiJson({
      candidates: [{ content: { parts: [{ text: "{}" }] } }],
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

  it("returns 502 when Gemini's text is empty", async () => {
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "" }] } }],
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

  it("reserves and settles credits when called with a client key", async () => {
    const boot = await bootstrapKey("watch-mem-1");
    const schema = {
      kind: "casual",
      title: "T",
      focusNote: "",
      openLoops: [],
      memoryItems: [],
      archiveTitle: null,
      archiveSummary: null,
      archiveOpenLoops: [],
    };
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: JSON.stringify(schema) }] } }],
      usageMetadata: { promptTokenCount: 50, candidatesTokenCount: 20, totalTokenCount: 70 },
    });
    const res = await memory(
      makeRequest({
        url: "http://t/memory",
        method: "POST",
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        body: { mode: "casual", recentMessages: [{ role: "user", text: "hi" }] },
      }),
    );
    expect(res.status).toBe(200);
    const snap = await billingStore().snapshot();
    const records = snap.usage.filter((u) => u.accountID === boot.account.accountID);
    expect(records).toHaveLength(1);
    expect(records[0].settledCredits).toBeGreaterThan(0);
  });

  it("rolls back reservation when Gemini returns garbage that cannot be parsed", async () => {
    const boot = await bootstrapKey("watch-mem-2");
    mockGeminiJson({
      candidates: [{ finishReason: "STOP", content: { parts: [{ text: "definitely not json" }] } }],
    });
    const before = await billingStore().snapshot();
    const beforeBalance = before.accounts[boot.account.accountID].creditBalance;
    const res = await memory(
      makeRequest({
        url: "http://t/memory",
        method: "POST",
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        body: { mode: "casual" },
      }),
    );
    expect(res.status).toBe(502);
    const after = await billingStore().snapshot();
    expect(after.accounts[boot.account.accountID].creditBalance).toBe(beforeBalance);
  });
});
