import { describe, expect, it } from "vitest";
import { buildChatRequest, buildMemoryRequest, buildTranscriptionRequest } from "@/lib/gemini/request";

describe("buildChatRequest", () => {
  it("merges consecutive same-role messages", () => {
    const req = buildChatRequest(
      {
        messages: [
          { role: "user", text: "hi" },
          { role: "user", text: "there" },
          { role: "assistant", text: "hello" },
        ],
      },
      "gemini-3-flash-preview",
    );
    expect(req.contents).toHaveLength(2);
    expect(req.contents[0]).toMatchObject({ role: "user" });
    expect(req.contents[0].parts).toEqual([{ text: "hi" }, { text: "there" }]);
    expect(req.contents[1]).toMatchObject({ role: "model" });
  });

  it("uses systemInstructionParts when provided, falling back to systemPrompt", () => {
    const withParts = buildChatRequest(
      { systemInstructionParts: [{ text: "A" }], systemPrompt: "B", messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(withParts.systemInstruction).toEqual({ parts: [{ text: "A" }] });

    const withPrompt = buildChatRequest(
      { systemPrompt: "B", messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(withPrompt.systemInstruction).toEqual({ parts: [{ text: "B" }] });

    const withNeither = buildChatRequest(
      { messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(withNeither.systemInstruction).toBeUndefined();
  });

  it("prefers modelResponseParts for assistant turns", () => {
    const req = buildChatRequest(
      {
        messages: [
          { role: "user", text: "Q" },
          { role: "assistant", text: "ignored", modelResponseParts: [{ text: "kept", thoughtSignature: "abc" }] },
        ],
      },
      "gemini-3-flash-preview",
    );
    const assistant = req.contents[1];
    expect(assistant.parts).toEqual([{ text: "kept", thoughtSignature: "abc" }]);
  });

  it("inlines image + base64 attachments", () => {
    const req = buildChatRequest(
      {
        messages: [
          {
            role: "user",
            text: "look",
            attachments: [{ mimeType: "image/png", base64Data: "AAA" }],
          },
        ],
      },
      "gemini-3-flash-preview",
    );
    expect(req.contents[0].parts).toContainEqual({
      inlineData: { mimeType: "image/png", data: "AAA" },
    });
    expect(req.generationConfig.mediaResolution).toBe("MEDIA_RESOLUTION_HIGH");
  });

  it("does NOT set mediaResolution when no images are present", () => {
    const req = buildChatRequest(
      { messages: [{ role: "user", text: "hi" }] },
      "gemini-3-flash-preview",
    );
    expect(req.generationConfig.mediaResolution).toBeUndefined();
  });

  it("maps thinkingIntensity → thinkingLevel for gemini-3.x", () => {
    const levels = {
      fast: "minimal",
      balanced: "medium",
      deep: "high",
      extreme: "high",
    } as const;
    for (const [intensity, expected] of Object.entries(levels)) {
      const req = buildChatRequest(
        { thinkingIntensity: intensity, messages: [{ role: "user", text: "x" }] },
        "gemini-3-flash-preview",
      );
      expect(req.generationConfig.thinkingConfig).toMatchObject({ thinkingLevel: expected, includeThoughts: true });
    }
  });

  it("maps thinkingIntensity → thinkingBudget for pre-3 models", () => {
    const budgets = { fast: 0, balanced: 8192, deep: 24576, extreme: -1 } as const;
    for (const [intensity, expected] of Object.entries(budgets)) {
      const req = buildChatRequest(
        { thinkingIntensity: intensity, messages: [{ role: "user", text: "x" }] },
        "gemini-2.5-flash",
      );
      expect(req.generationConfig.thinkingConfig).toMatchObject({ thinkingBudget: expected });
    }
  });

  it("drops thinkingLevel for gemini-3.1-pro + extreme (Swift quirk)", () => {
    const req = buildChatRequest(
      { thinkingIntensity: "extreme", messages: [{ role: "user", text: "x" }] },
      "gemini-3.1-pro-preview",
    );
    expect(req.generationConfig.thinkingConfig).toEqual({ includeThoughts: true });
  });

  it("forces temperature=1 + enableEnhancedCivicAnswers=true for gemini-3.x", () => {
    const req = buildChatRequest(
      { messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(req.generationConfig.temperature).toBe(1);
    expect(req.generationConfig.enableEnhancedCivicAnswers).toBe(true);
  });

  it("uses non-gemini-3 defaults for older models", () => {
    const req = buildChatRequest(
      { messages: [{ role: "user", text: "x" }] },
      "gemini-2.5-flash",
    );
    expect(req.generationConfig.temperature).toBe(0.65);
    expect(req.generationConfig.enableEnhancedCivicAnswers).toBeUndefined();
  });

  it("sets all four safety categories to OFF", () => {
    const req = buildChatRequest(
      { messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(req.safetySettings).toEqual([
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "OFF" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "OFF" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "OFF" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "OFF" },
    ]);
  });

  it("respects explicit maxOutputTokens; falls back to family defaults", () => {
    const explicit = buildChatRequest(
      { maxOutputTokens: 1024, messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(explicit.generationConfig.maxOutputTokens).toBe(1024);

    const implicit3 = buildChatRequest(
      { messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(implicit3.generationConfig.maxOutputTokens).toBe(65536);

    const implicitOld = buildChatRequest(
      { messages: [{ role: "user", text: "x" }] },
      "some-other-model",
    );
    expect(implicitOld.generationConfig.maxOutputTokens).toBe(8192);
  });

  it("includes tools only when flags are set", () => {
    const none = buildChatRequest({ messages: [{ role: "user", text: "x" }] }, "gemini-3-flash-preview");
    expect(none.tools).toBeUndefined();

    const both = buildChatRequest(
      { usesGoogleSearch: true, usesCodeExecution: true, messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(both.tools).toEqual([{ google_search: {} }, { code_execution: {} }]);
  });

  it("accepts snake_case flags on the wire (Swift compat)", () => {
    const req = buildChatRequest(
      { uses_google_search: true, system_prompt: "sys", messages: [{ role: "user", text: "x" }] },
      "gemini-3-flash-preview",
    );
    expect(req.tools).toEqual([{ google_search: {} }]);
    expect(req.systemInstruction).toEqual({ parts: [{ text: "sys" }] });
  });

  it("skips empty messages entirely", () => {
    const req = buildChatRequest(
      { messages: [{ role: "user" }, { role: "user", text: "ok" }] },
      "gemini-3-flash-preview",
    );
    expect(req.contents).toHaveLength(1);
  });
});

describe("buildTranscriptionRequest", () => {
  it("packages audio as an inlineData part and forces maxOutputTokens=5120", () => {
    const req = buildTranscriptionRequest(
      { prompt: "transcribe", audio: { mimeType: "audio/m4a", base64Data: "AUDIO" } },
      "gemini-3-flash-preview",
    );
    expect(req.contents[0].role).toBe("user");
    expect(req.contents[0].parts).toEqual([
      { text: "transcribe" },
      { inlineData: { mimeType: "audio/m4a", data: "AUDIO" } },
    ]);
    expect(req.generationConfig.maxOutputTokens).toBe(5120);
  });

  it("forces temperature=1 for gemini-3.x but 0.1 for older models", () => {
    expect(
      buildTranscriptionRequest({}, "gemini-3-flash-preview").generationConfig.temperature,
    ).toBe(1);
    expect(
      buildTranscriptionRequest({}, "gemini-2.5-flash").generationConfig.temperature,
    ).toBe(0.1);
  });
});

describe("buildMemoryRequest", () => {
  it("requests JSON-only output with the memory schema system prompt", () => {
    const req = buildMemoryRequest(
      {
        mode: "casual",
        conversationTitle: "Hello",
        recentMessages: [{ role: "user", text: "hi" }],
      },
      "gemini-3-flash-preview",
    );
    expect(req.generationConfig.responseMimeType).toBe("application/json");
    expect(req.generationConfig.maxOutputTokens).toBe(4096);
    expect(req.generationConfig.topP).toBe(0.9);
    const sys = (req.systemInstruction!.parts[0] as { text: string }).text;
    expect(sys).toMatch(/JSON only/i);
    expect(sys).toMatch(/memoryItems/);
  });

  it("includes existing focus + archive candidate sections when provided", () => {
    const req = buildMemoryRequest(
      {
        mode: "task",
        recentMessages: [{ role: "user", text: "recent" }],
        existingFocusState: { kind: "task", title: "Foo", openLoops: ["do thing"] },
        existingMemoryItems: ["fact 1"],
        archiveCandidateMessages: [{ role: "user", text: "old" }],
      },
      "gemini-3-flash-preview",
    );
    const content = (req.contents[0].parts[0] as { text: string }).text;
    expect(content).toContain("Existing focus state");
    expect(content).toContain("fact 1");
    expect(content).toContain("Archive candidate");
    expect(content).toContain("old");
  });

  it("marks archive absence explicitly", () => {
    const req = buildMemoryRequest({ mode: "casual" }, "gemini-3-flash-preview");
    const content = (req.contents[0].parts[0] as { text: string }).text;
    expect(content).toContain("Archive candidate: none");
  });
});
