import { beforeEach, describe, expect, it } from "vitest";
import { listConversations, getConversation } from "@/lib/store/conversations";
import { requestLog, type ActivityEntry } from "@/lib/store/request-log";
import { resetState } from "../helpers";

async function record(entry: Partial<ActivityEntry>) {
  await requestLog().recordActivity({
    id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    level: "success",
    category: "completed",
    message: "chat STOP",
    method: "POST",
    path: "/api/v1/chat/stream",
    statusCode: 200,
    ...entry,
  });
}

/** Build a cumulative-history payload that mirrors what the watch sends on
 *  turn N: [u1, a1, u2, a2, ..., u_N]. */
function cumulativeMessages(turnIndex: number): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  for (let i = 0; i < turnIndex; i++) {
    out.push({ role: "user", text: `u${i + 1}` });
    if (i < turnIndex - 1) out.push({ role: "assistant", text: `a${i + 1}` });
  }
  return out;
}

describe("conversations reconstruction", () => {
  beforeEach(resetState);

  it("returns empty when no chat requests captured", async () => {
    const list = await listConversations();
    expect(list).toEqual([]);
  });

  it("groups requests by x-aichat-conversation-id with high confidence", async () => {
    await record({
      conversationID: "conv-1",
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "hello world" }] },
      events: [{ type: "answer_delta_merged", data: { text: "hi!" }, at: new Date().toISOString() }],
    });
    const list = await listConversations();
    expect(list).toHaveLength(1);
    expect(list[0].id).toBe("conv-1");
    expect(list[0].confidence).toBe("high");
    expect(list[0].turns[0].userText).toBe("hello world");
    expect(list[0].turns[0].assistantText).toBe("hi!");
  });

  it("each turn surfaces the actual user input for that turn (not the first)", async () => {
    // Regression guard for the old `messagePreview` bug, which always returned
    // the first user message even though every request carries the full
    // history. After fix, turn N's userText must be `u_N`.
    const base = new Date("2026-04-01T00:00:00Z").getTime();
    for (let i = 1; i <= 3; i++) {
      await record({
        conversationID: "multi-turn",
        deviceID: "watch-A",
        timestamp: new Date(base + i * 1000).toISOString(),
        requestBody: { messages: cumulativeMessages(i) },
        events: [
          { type: "answer_delta_merged", data: { text: `a${i}` }, at: new Date().toISOString() },
        ],
      });
    }
    const conv = await getConversation("multi-turn");
    expect(conv?.turns).toHaveLength(3);
    expect(conv?.turns.map((t) => t.userText)).toEqual(["u1", "u2", "u3"]);
    expect(conv?.turns.map((t) => t.assistantText)).toEqual(["a1", "a2", "a3"]);
  });

  it("auto-grouping clusters all turns of one conversation into a single bucket", async () => {
    // Regression guard for the old `conversationKey` slicing bug, which
    // shattered a 5-turn conversation into ~3 buckets as the history grew.
    const base = new Date("2026-04-02T00:00:00Z").getTime();
    for (let i = 1; i <= 5; i++) {
      await record({
        deviceID: "watch-B",
        timestamp: new Date(base + i * 1000).toISOString(),
        requestBody: { messages: cumulativeMessages(i) },
      });
    }
    const list = await listConversations();
    expect(list).toHaveLength(1);
    expect(list[0].confidence).toBe("low");
    expect(list[0].turnCount).toBe(5);
    expect(list[0].turns.map((t) => t.userText)).toEqual(["u1", "u2", "u3", "u4", "u5"]);
  });

  it("auto-grouping disambiguates by deviceID even when the first message matches", async () => {
    await record({
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "hi" }] },
    });
    await record({
      deviceID: "watch-B",
      requestBody: { messages: [{ role: "user", text: "hi" }] },
    });
    const list = await listConversations();
    expect(list).toHaveLength(2);
    expect(new Set(list.map((c) => c.deviceID))).toEqual(new Set(["watch-A", "watch-B"]));
  });

  it("auto-grouping disambiguates two conversations from the same device with different first messages", async () => {
    await record({
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "topic A" }] },
    });
    await record({
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "topic B" }] },
    });
    const list = await listConversations();
    expect(list).toHaveLength(2);
    expect(new Set(list.map((c) => c.title))).toEqual(new Set(["topic A", "topic B"]));
  });

  it("explicit conversationID never merges with auto-keyed turns", async () => {
    await record({
      conversationID: "explicit-c1",
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "shared" }] },
    });
    await record({
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "shared" }] },
    });
    await record({
      deviceID: "watch-A",
      requestBody: { messages: [{ role: "user", text: "shared" }, { role: "assistant", text: "hi" }, { role: "user", text: "again" }] },
    });
    const list = await listConversations();
    expect(list).toHaveLength(2);
    const explicit = list.find((c) => c.id === "explicit-c1");
    const auto = list.find((c) => c.id !== "explicit-c1");
    expect(explicit?.turnCount).toBe(1);
    expect(explicit?.confidence).toBe("high");
    expect(auto?.turnCount).toBe(2);
    expect(auto?.confidence).toBe("low");
  });

  it("retries of the same turn appear as separate turns in one bucket", async () => {
    // Two requests with identical full-history payloads from the same device
    // should collapse into one conversation with two turns.
    const head = [{ role: "user", text: "about ml" }];
    await record({ deviceID: "watch-A", requestBody: { messages: head } });
    await record({ deviceID: "watch-A", requestBody: { messages: head } });
    const list = await listConversations();
    expect(list).toHaveLength(1);
    expect(list[0].confidence).toBe("low");
    expect(list[0].turnCount).toBe(2);
  });

  it("turns are returned in chronological order regardless of record order", async () => {
    const t1 = "2026-04-03T10:00:00.000Z";
    const t2 = "2026-04-03T10:00:01.000Z";
    const t3 = "2026-04-03T10:00:02.000Z";
    // Record out of order: t2, t1, t3.
    await record({
      conversationID: "ordered",
      deviceID: "d",
      timestamp: t2,
      requestBody: { messages: cumulativeMessages(2) },
    });
    await record({
      conversationID: "ordered",
      deviceID: "d",
      timestamp: t1,
      requestBody: { messages: cumulativeMessages(1) },
    });
    await record({
      conversationID: "ordered",
      deviceID: "d",
      timestamp: t3,
      requestBody: { messages: cumulativeMessages(3) },
    });
    const conv = await getConversation("ordered");
    expect(conv?.turns.map((t) => t.timestamp)).toEqual([t1, t2, t3]);
    expect(conv?.turns.map((t) => t.userText)).toEqual(["u1", "u2", "u3"]);
  });

  it("title is taken from the first turn's user message even after fix", async () => {
    const base = new Date("2026-04-04T00:00:00Z").getTime();
    for (let i = 1; i <= 3; i++) {
      await record({
        conversationID: "titled",
        deviceID: "d",
        timestamp: new Date(base + i * 1000).toISOString(),
        requestBody: { messages: cumulativeMessages(i) },
      });
    }
    const conv = await getConversation("titled");
    expect(conv?.title).toBe("u1");
  });

  it("sums tokens + credits across turns", async () => {
    await record({
      conversationID: "c",
      deviceID: "d",
      modelID: "gemini-3-flash-preview",
      inputTokens: 100,
      outputTokens: 50,
      settledCredits: 5,
      requestBody: { messages: [{ role: "user", text: "a" }] },
    });
    await record({
      conversationID: "c",
      deviceID: "d",
      modelID: "gemini-3-flash-preview",
      inputTokens: 200,
      outputTokens: 90,
      settledCredits: 9,
      requestBody: { messages: [{ role: "user", text: "a" }, { role: "assistant", text: "ok" }, { role: "user", text: "b" }] },
    });
    const list = await listConversations();
    expect(list[0].totalInputTokens).toBe(300);
    expect(list[0].totalOutputTokens).toBe(140);
    expect(list[0].totalCredits).toBe(14);
    expect(list[0].modelsUsed).toEqual(["gemini-3-flash-preview"]);
  });

  it("surfaces hasImages / hasAudio / hasErrors flags across the conversation", async () => {
    // First turn has an image attachment; second turn does not. The flag
    // should still report `hasImages: true` for the conversation as a whole.
    const base = new Date("2026-04-05T00:00:00Z").getTime();
    await record({
      level: "error",
      conversationID: "flags",
      deviceID: "d",
      timestamp: new Date(base + 1000).toISOString(),
      requestBody: {
        messages: [
          { role: "user", text: "x", attachments: [{ mimeType: "image/png", base64Data: "" }] },
        ],
      },
    });
    await record({
      conversationID: "flags",
      deviceID: "d",
      timestamp: new Date(base + 2000).toISOString(),
      requestBody: {
        messages: [
          { role: "user", text: "x", attachments: [{ mimeType: "image/png", base64Data: "" }] },
          { role: "assistant", text: "ok" },
          { role: "user", text: "follow up" },
        ],
      },
    });
    const conv = await getConversation("flags");
    expect(conv?.hasErrors).toBe(true);
    expect(conv?.hasImages).toBe(true);
  });

  it("free-text query matches assistant answer text", async () => {
    await record({
      conversationID: "a",
      deviceID: "d",
      requestBody: { messages: [{ role: "user", text: "greeting" }] },
      events: [{ type: "answer_delta_merged", data: { text: "unique-needle" }, at: new Date().toISOString() }],
    });
    await record({
      conversationID: "b",
      deviceID: "d",
      requestBody: { messages: [{ role: "user", text: "other" }] },
    });
    const hits = await listConversations({ query: "unique-needle" });
    expect(hits).toHaveLength(1);
    expect(hits[0].id).toBe("a");
  });

  it("getConversation returns the full reconstructed object by id", async () => {
    await record({
      conversationID: "c1",
      deviceID: "d",
      requestBody: { messages: [{ role: "user", text: "hi" }] },
    });
    const conv = await getConversation("c1");
    expect(conv?.title).toBe("hi");
  });

  it("handles an empty messages array without crashing", async () => {
    await record({
      conversationID: "empty",
      deviceID: "d",
      requestBody: { messages: [] },
    });
    const conv = await getConversation("empty");
    expect(conv?.turns).toHaveLength(1);
    expect(conv?.turns[0].userText).toBe("");
    expect(conv?.title).toBe("Untitled");
  });
});
