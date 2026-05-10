import { beforeEach, describe, expect, it } from "vitest";
import { GET as billingGet } from "@/app/api/admin/billing/route";
import { GET as conversationsList } from "@/app/api/admin/conversations/route";
import { GET as conversationDetail } from "@/app/api/admin/conversations/[id]/route";
import { GET as sessionGet } from "@/app/api/admin/session/route";
import { GET as requestsStream } from "@/app/api/admin/requests/stream/route";
import { POST as login } from "@/app/api/admin/login/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { requestLog } from "@/lib/store/request-log";
import { makeRequest, resetState } from "../helpers";

async function signIn() {
  await login(
    makeRequest({
      url: "http://test/login",
      method: "POST",
      body: { username: "admin", password: "testpassword" },
    }),
  );
}

async function seedDevice() {
  const res = await bootstrap(
    makeRequest({
      url: "http://test/api/v1/activation/bootstrap",
      method: "POST",
      body: { deviceID: "watch-1", platform: "watch" },
    }),
  );
  return res.json() as Promise<{
    account: { accountID: string };
    device: { deviceID: string };
  }>;
}

describe("GET /api/admin/billing", () => {
  beforeEach(resetState);

  it("returns 401 without an admin session", async () => {
    const res = await billingGet();
    expect(res.status).toBe(401);
  });

  it("returns the full billing snapshot to a logged-in admin", async () => {
    await signIn();
    await seedDevice();
    const res = await billingGet();
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      accounts: unknown[];
      devices: unknown[];
      keys: unknown[];
      grants: unknown[];
      plans: unknown[];
    };
    expect(Array.isArray(body.accounts)).toBe(true);
    expect(Array.isArray(body.devices)).toBe(true);
    expect(Array.isArray(body.plans)).toBe(true);
    expect(body.accounts.length).toBeGreaterThan(0);
  });
});

describe("GET /api/admin/session", () => {
  beforeEach(resetState);

  it("returns null session when no cookie is present", async () => {
    const res = await sessionGet();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { session: unknown };
    expect(body.session).toBeNull();
  });

  it("returns the active session after login", async () => {
    await signIn();
    const res = await sessionGet();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { session: { sub: string; role: string } | null };
    expect(body.session?.sub).toBe("admin");
    expect(body.session?.role).toBe("operator");
  });
});

describe("GET /api/admin/conversations", () => {
  beforeEach(resetState);

  it("returns 401 without a session", async () => {
    const res = await conversationsList(makeRequest({ url: "http://t/conv" }));
    expect(res.status).toBe(401);
  });

  it("returns an empty list when no chat traffic has occurred", async () => {
    await signIn();
    const res = await conversationsList(makeRequest({ url: "http://t/conv" }));
    expect(res.status).toBe(200);
    const body = (await res.json()) as { conversations: unknown[] };
    expect(body.conversations).toEqual([]);
  });

  it("groups recorded chat-stream activity into a conversation", async () => {
    await signIn();
    // Inject a synthetic activity entry that listConversations() will match.
    await requestLog().recordActivity({
      id: "act_1",
      timestamp: new Date().toISOString(),
      level: "success",
      category: "completed",
      message: "ok",
      path: "/api/v1/chat/stream",
      modelID: "gemini-3-flash-preview",
      conversationID: "conv-test-1",
      requestBody: { messages: [{ role: "user", text: "Hello world" }] },
      events: [
        { type: "answer_delta_merged", data: { text: "Hi back" }, at: new Date().toISOString() },
      ],
      inputTokens: 5,
      outputTokens: 10,
      settledCredits: 7,
      finishReason: "STOP",
    });
    const res = await conversationsList(makeRequest({ url: "http://t/conv?limit=10" }));
    expect(res.status).toBe(200);
    const body = (await res.json()) as { conversations: { id: string; turnCount: number }[] };
    expect(body.conversations.length).toBe(1);
    expect(body.conversations[0].turnCount).toBe(1);
  });

  it("supports query filters (q + modelID) without crashing", async () => {
    await signIn();
    await requestLog().recordActivity({
      id: "act_2",
      timestamp: new Date().toISOString(),
      level: "success",
      category: "completed",
      message: "ok",
      path: "/api/v1/chat/stream",
      modelID: "gemini-3-pro",
      conversationID: "conv-test-2",
      requestBody: { messages: [{ role: "user", text: "needle" }] },
      events: [
        { type: "answer_delta_merged", data: { text: "haystack" }, at: new Date().toISOString() },
      ],
    });
    const res = await conversationsList(
      makeRequest({
        url: "http://t/conv?q=needle&modelID=gemini-3-pro&hasErrors=0&hasImages=0&hasAudio=0",
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { conversations: unknown[] };
    expect(body.conversations.length).toBe(1);
  });
});

describe("GET /api/admin/conversations/[id]", () => {
  beforeEach(resetState);

  it("returns 401 without a session", async () => {
    const res = await conversationDetail(
      makeRequest({ url: "http://t/conv/xyz" }),
      { params: Promise.resolve({ id: "xyz" }) },
    );
    expect(res.status).toBe(401);
  });

  it("returns 404 for an unknown conversation id", async () => {
    await signIn();
    const res = await conversationDetail(
      makeRequest({ url: "http://t/conv/missing" }),
      { params: Promise.resolve({ id: "missing" }) },
    );
    expect(res.status).toBe(404);
  });

  it("returns the matching conversation when present", async () => {
    await signIn();
    await requestLog().recordActivity({
      id: "act_x",
      timestamp: new Date().toISOString(),
      level: "success",
      category: "completed",
      message: "ok",
      path: "/api/v1/chat/stream",
      modelID: "gemini-3-flash-preview",
      conversationID: "conv-aa",
      requestBody: { messages: [{ role: "user", text: "ping" }] },
      events: [
        { type: "answer_delta_merged", data: { text: "pong" }, at: new Date().toISOString() },
      ],
    });
    const res = await conversationDetail(
      makeRequest({ url: "http://t/conv/conv-aa" }),
      { params: Promise.resolve({ id: "conv-aa" }) },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { conversation: { id: string; turns: unknown[] } };
    expect(body.conversation.id).toBe("conv-aa");
    expect(body.conversation.turns.length).toBe(1);
  });

  it("rebuilds a 3-turn cumulative-history conversation with correct per-turn user text", async () => {
    // End-to-end regression guard: simulate a real watch session where every
    // request carries the full prior history. The rebuilt conversation must
    // expose u1/u2/u3 across the three turns (not three copies of u1).
    await signIn();
    const base = new Date("2026-04-10T00:00:00Z").getTime();
    const turns = [
      { messages: [{ role: "user", text: "u1" }], answer: "a1" },
      { messages: [
        { role: "user", text: "u1" },
        { role: "assistant", text: "a1" },
        { role: "user", text: "u2" },
      ], answer: "a2" },
      { messages: [
        { role: "user", text: "u1" },
        { role: "assistant", text: "a1" },
        { role: "user", text: "u2" },
        { role: "assistant", text: "a2" },
        { role: "user", text: "u3" },
      ], answer: "a3" },
    ];
    for (let i = 0; i < turns.length; i++) {
      await requestLog().recordActivity({
        id: `multi_${i}`,
        timestamp: new Date(base + (i + 1) * 1000).toISOString(),
        level: "success",
        category: "completed",
        message: "ok",
        path: "/api/v1/chat/stream",
        conversationID: "multi-route",
        deviceID: "watch-A",
        requestBody: { messages: turns[i].messages },
        events: [
          { type: "answer_delta_merged", data: { text: turns[i].answer }, at: new Date().toISOString() },
        ],
      });
    }
    const res = await conversationDetail(
      makeRequest({ url: "http://t/conv/multi-route" }),
      { params: Promise.resolve({ id: "multi-route" }) },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      conversation: {
        id: string;
        title: string;
        turnCount: number;
        turns: { userText?: string; assistantText?: string }[];
      };
    };
    expect(body.conversation.id).toBe("multi-route");
    expect(body.conversation.turnCount).toBe(3);
    expect(body.conversation.title).toBe("u1");
    expect(body.conversation.turns.map((t) => t.userText)).toEqual(["u1", "u2", "u3"]);
    expect(body.conversation.turns.map((t) => t.assistantText)).toEqual(["a1", "a2", "a3"]);
  });
});

describe("GET /api/admin/requests/stream", () => {
  beforeEach(resetState);

  it("returns 401 without a session", async () => {
    const res = await requestsStream();
    expect(res.status).toBe(401);
  });

  it("opens an SSE stream that emits a ping event and forwards activity", async () => {
    await signIn();
    const res = await requestsStream();
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toContain("text/event-stream");

    const reader = res.body!.getReader();
    const decoder = new TextDecoder();

    // First chunk: should contain the initial ping event written synchronously
    // by the start() callback.
    const first = await reader.read();
    expect(first.done).toBe(false);
    const text = decoder.decode(first.value!);
    expect(text).toContain("event: ping");

    // Push an activity entry; the listener attached in start() should fan it
    // out to our stream.
    const activityPromise = reader.read();
    await requestLog().recordActivity({
      id: "stream_evt",
      timestamp: new Date().toISOString(),
      level: "info",
      category: "request",
      message: "hello",
      path: "/api/v1/chat/stream",
    });
    const second = await activityPromise;
    expect(second.done).toBe(false);
    const activityText = decoder.decode(second.value!);
    expect(activityText).toContain("event: activity");

    // Cancel to trigger the stream's cancel() callback (cleans up listener).
    await reader.cancel();
  });
});
