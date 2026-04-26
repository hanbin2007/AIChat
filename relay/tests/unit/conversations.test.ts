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

  it("groups retries of the same turn when first-3 messages match", async () => {
    // Two requests sharing the same first three messages hash to the same
    // bucket. A follow-up turn that adds a fourth message is a separate bucket
    // by design — matches the current implementation of conversationKey().
    const head = [
      { role: "user", text: "about ml" },
      { role: "assistant", text: "sure" },
      { role: "user", text: "more" },
    ];
    await record({ deviceID: "watch-A", requestBody: { messages: head } });
    await record({ deviceID: "watch-A", requestBody: { messages: head } });
    const list = await listConversations();
    expect(list).toHaveLength(1);
    expect(list[0].confidence).toBe("low");
    expect(list[0].turnCount).toBe(2);
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
      requestBody: { messages: [{ role: "user", text: "a" }, { role: "user", text: "b" }] },
    });
    const list = await listConversations();
    expect(list[0].totalInputTokens).toBe(300);
    expect(list[0].totalOutputTokens).toBe(140);
    expect(list[0].totalCredits).toBe(14);
    expect(list[0].modelsUsed).toEqual(["gemini-3-flash-preview"]);
  });

  it("surfaces hasImages / hasAudio / hasErrors flags", async () => {
    await record({
      level: "error",
      conversationID: "c",
      deviceID: "d",
      requestBody: {
        messages: [{ role: "user", text: "x", attachments: [{ mimeType: "image/png", base64Data: "" }] }],
      },
    });
    const list = await listConversations();
    expect(list[0].hasErrors).toBe(true);
    expect(list[0].hasImages).toBe(true);
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
});
