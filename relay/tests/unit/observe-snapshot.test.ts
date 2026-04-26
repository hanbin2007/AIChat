/**
 * Verifies `safeRequestSnapshot` strips raw bytes / full conversation slices
 * from request bodies so the activity log never contains user PII or large
 * audio blobs.
 */

import { beforeEach, describe, expect, it } from "vitest";
import {
  safeRequestSnapshot,
  cacheIdempotentResponse,
  getIdempotentResponse,
} from "@/lib/api/observe";
import { resetState } from "../helpers";

describe("safeRequestSnapshot", () => {
  beforeEach(resetState);

  it("replaces audio base64 with a length+mime summary", () => {
    const body = {
      model: "gemini-3-flash-preview",
      prompt: "transcribe this please",
      audio: { mimeType: "audio/wav", base64Data: "AAAA".repeat(2048), filename: "clip.wav" },
    };
    const snap = safeRequestSnapshot(body, "/api/v1/audio/transcribe") as Record<string, unknown>;
    const audio = snap.audio as Record<string, unknown>;
    expect(audio.base64Data).toBeUndefined();
    expect(audio.mimeType).toBe("audio/wav");
    expect(typeof audio.lengthBytes).toBe("number");
    expect((audio.lengthBytes as number)).toBeGreaterThan(0);
    expect(audio.filename).toBe("clip.wav");
    expect(snap.prompt).toBe("transcribe this please");
  });

  it("replaces memory recentMessages with a count+charCount summary", () => {
    const body = {
      mode: "casual",
      conversationTitle: "weekend plans",
      recentMessages: [
        { role: "user", text: "hi" },
        { role: "assistant", text: "hello there" },
      ],
      archiveCandidateMessages: [],
    };
    const snap = safeRequestSnapshot(body, "/api/v1/memory/extract") as Record<string, unknown>;
    expect(snap.recentMessages).toEqual({ count: 2, charCount: 13 });
    expect(snap.archiveCandidateMessages).toEqual({ count: 0, charCount: 0 });
    expect(snap.conversationTitle).toBe("weekend plans");
  });

  it("strips chat message attachments to mime+lengthBytes summaries", () => {
    const body = {
      model: "gemini-3-flash-preview",
      messages: [
        { role: "user", text: "hi", attachments: [] },
        {
          role: "user",
          text: "look",
          attachments: [
            { mimeType: "image/png", base64Data: "AAAA".repeat(64), filename: "p.png" },
          ],
        },
      ],
    };
    const snap = safeRequestSnapshot(body, "/api/v1/chat/stream") as Record<string, unknown>;
    const messages = snap.messages as Record<string, unknown>[];
    const attached = messages[1].attachments as Record<string, unknown>[];
    expect(attached[0].base64Data).toBeUndefined();
    expect(attached[0].mimeType).toBe("image/png");
    expect(typeof attached[0].lengthBytes).toBe("number");
  });

  it("returns the input untouched for unknown endpoints when no rules match", () => {
    const body = { foo: "bar", baz: 42 };
    const snap = safeRequestSnapshot(body, "/api/v1/account/pairing-token") as Record<string, unknown>;
    expect(snap.foo).toBe("bar");
    expect(snap.baz).toBe(42);
  });
});

describe("idempotency cache", () => {
  beforeEach(resetState);

  it("round-trips a stored response by (account, key)", () => {
    expect(getIdempotentResponse("acc-1", "k-1")).toBeUndefined();
    cacheIdempotentResponse("acc-1", "k-1", 200, JSON.stringify({ ok: true }));
    const hit = getIdempotentResponse("acc-1", "k-1");
    expect(hit).toEqual({ statusCode: 200, responseBody: JSON.stringify({ ok: true }) });
  });

  it("ignores misses when the account or key is missing", () => {
    cacheIdempotentResponse("acc-1", "k-1", 200, "{}");
    expect(getIdempotentResponse(undefined, "k-1")).toBeUndefined();
    expect(getIdempotentResponse("acc-1", undefined)).toBeUndefined();
    expect(getIdempotentResponse("acc-1", "k-2")).toBeUndefined();
  });
});
