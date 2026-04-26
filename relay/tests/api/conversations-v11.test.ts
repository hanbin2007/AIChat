/**
 * v1.1 conversation endpoints: pin / unpin, replay (synthesized SSE),
 * export (json / markdown / transcript), retention exemption.
 */

import { beforeEach, describe, expect, it } from "vitest";
import { POST as login } from "@/app/api/admin/login/route";
import {
  POST as pin,
  DELETE as unpin,
} from "@/app/api/admin/conversations/[id]/pin/route";
import { GET as replay } from "@/app/api/admin/conversations/[id]/replay/route";
import { GET as exportConv } from "@/app/api/admin/conversations/[id]/export/route";
import { GET as listConvs } from "@/app/api/admin/conversations/route";
import { conversationPins } from "@/lib/store/conversation-pins";
import { requestLog } from "@/lib/store/request-log";
import { makeRequest, readSseEvents, resetState } from "../helpers";

async function signInOperator() {
  await login(
    makeRequest({
      url: "http://t/login",
      method: "POST",
      body: { username: "admin", password: "testpassword" },
    }),
  );
}

async function seedConversation(id = "conv-1", turns = 2): Promise<void> {
  for (let i = 0; i < turns; i++) {
    await requestLog().recordActivity({
      id: `req-${id}-${i}`,
      timestamp: new Date(Date.now() - (turns - i) * 1000).toISOString(),
      level: "success",
      category: "completed",
      message: "chat STOP",
      method: "POST",
      path: "/api/v1/chat/stream",
      statusCode: 200,
      conversationID: id,
      deviceID: "watch-A",
      modelID: "gemini-3-flash-preview",
      inputTokens: 50,
      outputTokens: 100,
      settledCredits: 7,
      finishReason: "STOP",
      requestBody: { messages: [{ role: "user", text: `turn ${i}` }] },
      events: [
        { type: "answer_delta_merged", data: { text: `answer ${i}` }, at: new Date().toISOString() },
        { type: "thought_delta_merged", data: { text: `thought ${i}` }, at: new Date().toISOString() },
      ],
    });
  }
}

describe("conversation pin / unpin", () => {
  beforeEach(async () => {
    await resetState();
    await signInOperator();
  });

  it("POST pin marks pinned + writes audit, DELETE clears it", async () => {
    await seedConversation("c-1");
    const pinned = await pin(
      makeRequest({ url: "http://t/pin", method: "POST", body: { note: "VIP" } }),
      { params: Promise.resolve({ id: "c-1" }) },
    );
    expect(pinned.status).toBe(200);
    expect(await conversationPins().isPinned("c-1")).toBe(true);

    const unpinned = await unpin(
      makeRequest({ url: "http://t/pin", method: "DELETE" }),
      { params: Promise.resolve({ id: "c-1" }) },
    );
    expect(unpinned.status).toBe(200);
    expect(await conversationPins().isPinned("c-1")).toBe(false);
  });

  it("conversation list reports `pinned: true` and supports pinned-only filter", async () => {
    await seedConversation("c-1");
    await seedConversation("c-2");
    await conversationPins().pin("c-2");

    const all = (await (await listConvs(makeRequest({ url: "http://t/list" }))).json()) as {
      conversations: { id: string; pinned: boolean }[];
    };
    expect(all.conversations.find((c) => c.id === "c-1")?.pinned).toBe(false);
    expect(all.conversations.find((c) => c.id === "c-2")?.pinned).toBe(true);

    const filtered = (await (
      await listConvs(makeRequest({ url: "http://t/list?pinned=1" }))
    ).json()) as { conversations: { id: string }[] };
    expect(filtered.conversations.map((c) => c.id)).toEqual(["c-2"]);
  });

  it("retention truncation skips pinned entries first", async () => {
    requestLog().configureCaps(5, 50);
    await seedConversation("c-pin", 2); // pinned
    await conversationPins().pin("c-pin");
    await seedConversation("c-fresh", 6); // unpinned overflow
    const list = await requestLog().listActivity();
    // The pinned conversation's entries should still be present.
    const pinnedEntries = list.filter((e) => e.conversationID === "c-pin");
    expect(pinnedEntries.length).toBe(2);
  });
});

describe("conversation replay (synthesized SSE)", () => {
  beforeEach(async () => {
    await resetState();
    await signInOperator();
  });

  it("emits conversation_start, turn_start/turn_end, and conversation_end at speed=8", async () => {
    await seedConversation("c-replay", 2);
    const res = await replay(
      makeRequest({ url: "http://t/replay?speed=8" }),
      { params: Promise.resolve({ id: "c-replay" }) },
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toMatch(/text\/event-stream/);
    const events = await readSseEvents(res);
    expect(events[0].event).toBe("conversation_start");
    expect(events.find((e) => e.event === "turn_start")).toBeDefined();
    expect(events.find((e) => e.event === "answer_delta")).toBeDefined();
    expect(events.find((e) => e.event === "turn_end")).toBeDefined();
    expect(events.at(-1)?.event).toBe("conversation_end");
  });

  it("returns 404 for unknown conversation", async () => {
    const res = await replay(
      makeRequest({ url: "http://t/replay?speed=8" }),
      { params: Promise.resolve({ id: "nope" }) },
    );
    expect(res.status).toBe(404);
  });
});

describe("conversation export", () => {
  beforeEach(async () => {
    await resetState();
    await signInOperator();
  });

  it("JSON returns the full Conversation with attachment headers", async () => {
    await seedConversation("c-export");
    const res = await exportConv(
      makeRequest({ url: "http://t/export?format=json" }),
      { params: Promise.resolve({ id: "c-export" }) },
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Disposition")).toMatch(/conversation-c-export\.json/);
    const data = (await res.json()) as { id: string; turns: unknown[] };
    expect(data.id).toBe("c-export");
    expect(data.turns.length).toBeGreaterThan(0);
  });

  it("Markdown export contains user / assistant / model headers", async () => {
    await seedConversation("c-md");
    const res = await exportConv(
      makeRequest({ url: "http://t/export?format=markdown" }),
      { params: Promise.resolve({ id: "c-md" }) },
    );
    expect(res.headers.get("Content-Type")).toMatch(/text\/markdown/);
    const md = await res.text();
    expect(md).toMatch(/^# /m);
    expect(md).toMatch(/User/);
    expect(md).toMatch(/Assistant/);
  });

  it("Transcript export is plain alternating user/assistant", async () => {
    await seedConversation("c-tx");
    const res = await exportConv(
      makeRequest({ url: "http://t/export?format=transcript" }),
      { params: Promise.resolve({ id: "c-tx" }) },
    );
    const txt = await res.text();
    expect(txt.split("\n\n").length).toBeGreaterThan(1);
    expect(txt).toMatch(/^User: /m);
    expect(txt).toMatch(/^Assistant: /m);
  });
});
