import { describe, expect, it } from "vitest";
import { buildChatRequest, buildMemoryRequest, buildTranscriptionRequest } from "@/lib/gemini/request";

/**
 * Wire-compatibility golden snapshots.
 *
 * These lock down the Gemini request body produced for a realistic payload
 * from the macOS AIChat Relay / Swift watch client. If the Swift client ever
 * drifts (e.g. a new thinkingIntensity value, a new role, a different key
 * casing), these snapshots fail loudly — which is the point.
 *
 * The input bodies below intentionally use snake_case keys for some fields
 * and camelCase for others, to exercise the dual-key codec.
 */

describe("Wire-compat golden — chat/stream", () => {
  it("Watch app multi-turn with thought signatures + image attachment", () => {
    const body = {
      model: "gemini-3-flash-preview",
      system_prompt: "You are a concise assistant.",
      thinking_intensity: "balanced",
      include_thoughts: true,
      uses_google_search: true,
      messages: [
        { role: "user", text: "帮我看看这张截图里有什么 bug" },
        {
          role: "user",
          attachments: [{ mime_type: "image/png", base64_data: "UE5HBASE64" }],
        },
        {
          role: "assistant",
          model_response_parts: [
            { text: "屏幕截图显示：" },
            { text: " 404 Not Found", thoughtSignature: "sig-1" },
          ],
        },
        { role: "user", text: "那我应该怎么修复？" },
      ],
    };
    const out = buildChatRequest(body, "gemini-3-flash-preview");
    expect(out).toMatchInlineSnapshot(`
      {
        "contents": [
          {
            "parts": [
              {
                "text": "帮我看看这张截图里有什么 bug",
              },
              {
                "inlineData": {
                  "data": "UE5HBASE64",
                  "mimeType": "image/png",
                },
              },
            ],
            "role": "user",
          },
          {
            "parts": [
              {
                "text": "屏幕截图显示：",
              },
              {
                "text": " 404 Not Found",
                "thoughtSignature": "sig-1",
              },
            ],
            "role": "model",
          },
          {
            "parts": [
              {
                "text": "那我应该怎么修复？",
              },
            ],
            "role": "user",
          },
        ],
        "generationConfig": {
          "enableEnhancedCivicAnswers": true,
          "maxOutputTokens": 65536,
          "mediaResolution": "MEDIA_RESOLUTION_HIGH",
          "temperature": 1,
          "thinkingConfig": {
            "includeThoughts": true,
            "thinkingLevel": "medium",
          },
          "topP": 0.95,
        },
        "safetySettings": [
          {
            "category": "HARM_CATEGORY_HARASSMENT",
            "threshold": "OFF",
          },
          {
            "category": "HARM_CATEGORY_HATE_SPEECH",
            "threshold": "OFF",
          },
          {
            "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "threshold": "OFF",
          },
          {
            "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
            "threshold": "OFF",
          },
        ],
        "systemInstruction": {
          "parts": [
            {
              "text": "You are a concise assistant.",
            },
          ],
        },
        "tools": [
          {
            "google_search": {},
          },
        ],
      }
    `);
  });

  it("gemini-3.1-pro + extreme intensity drops thinkingLevel (Swift quirk)", () => {
    const out = buildChatRequest(
      {
        model: "gemini-3.1-pro-preview",
        thinkingIntensity: "extreme",
        includeThoughts: true,
        messages: [{ role: "user", text: "hi" }],
      },
      "gemini-3.1-pro-preview",
    );
    expect(out.generationConfig.thinkingConfig).toEqual({ includeThoughts: true });
  });

  it("gemini-2.5-flash maps 'deep' → thinkingBudget=24576 with temperature=0.65", () => {
    const out = buildChatRequest(
      {
        thinkingIntensity: "deep",
        messages: [{ role: "user", text: "hi" }],
      },
      "gemini-2.5-flash",
    );
    expect(out.generationConfig).toMatchObject({
      temperature: 0.65,
      topP: 0.95,
      thinkingConfig: { thinkingBudget: 24576 },
    });
    expect(out.generationConfig.enableEnhancedCivicAnswers).toBeUndefined();
  });
});

describe("Wire-compat golden — audio/transcribe", () => {
  it("packages the audio inline and forces maxOutputTokens=5120", () => {
    const out = buildTranscriptionRequest(
      {
        prompt: "请转写",
        audio: { mime_type: "audio/m4a", base64_data: "AUDIO" },
        system_prompt: "Transcribe verbatim.",
      },
      "gemini-3-flash-preview",
    );
    expect(out).toMatchInlineSnapshot(`
      {
        "contents": [
          {
            "parts": [
              {
                "text": "请转写",
              },
              {
                "inlineData": {
                  "data": "AUDIO",
                  "mimeType": "audio/m4a",
                },
              },
            ],
            "role": "user",
          },
        ],
        "generationConfig": {
          "maxOutputTokens": 5120,
          "temperature": 1,
          "topP": 0.95,
        },
        "systemInstruction": {
          "parts": [
            {
              "text": "Transcribe verbatim.",
            },
          ],
        },
      }
    `);
  });
});

describe("Wire-compat golden — memory/extract", () => {
  it("emits JSON-only generationConfig with the canonical system schema", () => {
    const out = buildMemoryRequest(
      {
        mode: "task",
        conversationTitle: "项目计划",
        recentMessages: [{ role: "user", text: "做个规划" }],
        existingMemoryItems: ["喜欢用中文"],
      },
      "gemini-3-flash-preview",
    );
    expect(out.generationConfig).toEqual({
      maxOutputTokens: 4096,
      responseMimeType: "application/json",
      temperature: 1,
      topP: 0.9,
    });
    const sys = (out.systemInstruction!.parts[0] as { text: string }).text;
    expect(sys).toMatch(/memoryItems/);
    expect(sys).toMatch(/archiveTitle/);
    const userText = (out.contents[0].parts[0] as { text: string }).text;
    expect(userText).toContain("项目计划");
    expect(userText).toContain("喜欢用中文");
  });
});
