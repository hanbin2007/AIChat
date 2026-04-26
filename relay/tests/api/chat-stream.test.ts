import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { POST as chat } from "@/app/api/v1/chat/stream/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { billingStore } from "@/lib/store/billing-store";
import { makeRequest, mockGeminiStream, readSseEvents, resetState } from "../helpers";

function sse(payload: unknown): string {
  return `data: ${JSON.stringify(payload)}\n\n`;
}

describe("POST /api/v1/chat/stream", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("returns 401 without a bearer", async () => {
    const res = await chat(
      makeRequest({
        url: "http://test/api/v1/chat/stream",
        method: "POST",
        body: { messages: [{ role: "user", text: "hi" }] },
      }),
    );
    expect(res.status).toBe(401);
  });

  it("rejects an admin bearer token on metered chat (per-device key required)", async () => {
    const res = await chat(
      makeRequest({
        url: "http://test/api/v1/chat/stream",
        method: "POST",
        headers: { Authorization: "Bearer test-bearer-token" },
        body: { messages: [{ role: "user", text: "hi" }] },
      }),
    );
    expect(res.status).toBe(401);
    const body = (await res.json()) as { message: string };
    expect(body.message).toMatch(/Per-device key required/);
  });

  it("returns 400 for malformed JSON", async () => {
    const boot = await (
      await bootstrap(
        makeRequest({
          url: "http://test/api/v1/activation/bootstrap",
          method: "POST",
          body: { deviceID: "d-malformed", platform: "watch" },
        }),
      )
    ).json();
    const req = new Request("http://test/api/v1/chat/stream", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${boot.key.keyValue}` },
      body: "{ not json",
    });
    const res = await chat(req);
    expect(res.status).toBe(400);
  });

  it("reserves and settles credits when called with a client key", async () => {
    const boot = await (
      await bootstrap(
        makeRequest({
          url: "http://test/api/v1/activation/bootstrap",
          method: "POST",
          body: { deviceID: "d1", platform: "watch" },
        }),
      )
    ).json();
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "hey" }] } }] }),
      sse({
        candidates: [{ finishReason: "STOP", content: { parts: [] } }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 20, totalTokenCount: 30 },
      }),
    ]);
    const res = await chat(
      makeRequest({
        url: "http://test/api/v1/chat/stream",
        method: "POST",
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        body: { messages: [{ role: "user", text: "hi there" }] },
      }),
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toContain("text/event-stream");
    expect(res.headers.get("X-Accel-Buffering")).toBe("no");
    const events = await readSseEvents(res);
    const answer = events.find((e) => e.event === "answer_delta");
    const done = events.find((e) => e.event === "done");
    expect(answer?.data).toContain("hey");
    expect(done?.data).toContain("STOP");
    const snap = await billingStore().snapshot();
    const records = snap.usage.filter((u) => u.accountID === boot.account.accountID);
    expect(records).toHaveLength(1);
    expect(records[0].settledCredits).toBeGreaterThan(0);
    expect(records[0].inputTokens).toBe(10);
    expect(records[0].outputTokens).toBe(20);
  });

  it("rolls back the reservation when Gemini fails mid-stream", async () => {
    const boot = await (
      await bootstrap(
        makeRequest({
          url: "http://test/api/v1/activation/bootstrap",
          method: "POST",
          body: { deviceID: "d2", platform: "watch" },
        }),
      )
    ).json();
    mockGeminiStream([
      sse({ candidates: [{ content: { parts: [{ text: "partial" }] } }] }),
    ]);
    const res = await chat(
      makeRequest({
        url: "http://test/api/v1/chat/stream",
        method: "POST",
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        body: { messages: [{ role: "user", text: "hi" }] },
      }),
    );
    const events = await readSseEvents(res);
    expect(events.some((e) => e.event === "error")).toBe(true);
    const snap = await billingStore().snapshot();
    const account = snap.accounts[boot.account.accountID];
    expect(account.creditBalance).toBe(800);
  });
});
