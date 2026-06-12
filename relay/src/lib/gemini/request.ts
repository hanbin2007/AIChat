/**
 * Transform the watch app's request body into a Gemini generateContent body.
 * Behavior mirrors `AIChat Relay/GeminiRelayBridge.swift` exactly:
 *   · thinking intensity → thinkingConfig (family-specific)
 *   · all four HARM_CATEGORY_* safety settings OFF
 *   · temperature=1.0 + enableEnhancedCivicAnswers for gemini-3.x
 *   · MEDIA_RESOLUTION_HIGH when any message carries an image attachment
 */

import { pick } from "./dual-key";
import { maxOutputTokensForModel } from "@/lib/billing/metering";

type Intensity = "fast" | "balanced" | "deep" | "extreme";

function thinkingConfigFor(model: string, intensity: Intensity | undefined, includeThoughts: boolean) {
  const modelKey = String(model || "");
  if (modelKey.startsWith("gemini-3")) {
    if (modelKey.startsWith("gemini-3.1-pro") && intensity === "extreme") {
      return { includeThoughts };
    }
    const level = { fast: "minimal", balanced: "medium", deep: "high", extreme: "high" }[intensity ?? "balanced"];
    return { thinkingLevel: level, includeThoughts };
  }
  const budget = { fast: 0, balanced: 8192, deep: 24576, extreme: -1 }[intensity ?? "balanced"];
  return { thinkingBudget: budget, includeThoughts };
}

function temperatureFor(model: string, fallback: number): number {
  return String(model || "").startsWith("gemini-3") ? 1 : fallback;
}

function chatSafetySettings() {
  return [
    { category: "HARM_CATEGORY_HARASSMENT", threshold: "OFF" },
    { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "OFF" },
    { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "OFF" },
    { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "OFF" },
  ];
}

function toolsFor(body: Record<string, unknown>) {
  const tools: Record<string, unknown>[] = [];
  if (pick(body, "usesGoogleSearch", "uses_google_search") === true) tools.push({ google_search: {} });
  if (pick(body, "usesCodeExecution", "uses_code_execution") === true) tools.push({ code_execution: {} });
  return tools.length > 0 ? tools : undefined;
}

function hasImageAttachment(messages: Record<string, unknown>[]): boolean {
  return messages.some((m) => {
    const attachments = pick<Record<string, unknown>[]>(m, "attachments") ?? [];
    return attachments.some((a) => {
      const mime = String(pick<string>(a, "mimeType", "mime_type") ?? "").toLowerCase();
      return mime.startsWith("image/");
    });
  });
}

export function buildChatRequest(body: Record<string, unknown>, model: string) {
  const systemPrompt = pick<string>(body, "systemPrompt", "system_prompt");
  const systemInstructionParts = pick<Record<string, unknown>[]>(body, "systemInstructionParts", "system_instruction_parts");
  const messages = Array.isArray(body.messages) ? (body.messages as Record<string, unknown>[]) : [];
  const contents = messages.reduce<Record<string, unknown>[]>((acc, message) => {
    const role = pick<string>(message, "role") === "assistant" ? "model" : "user";
    const modelResponseParts = pick<Record<string, unknown>[]>(message, "modelResponseParts", "model_response_parts");
    let parts: Record<string, unknown>[];
    if (role === "model" && Array.isArray(modelResponseParts) && modelResponseParts.length > 0) {
      parts = modelResponseParts;
    } else {
      parts = [];
      const text = pick<string>(message, "text");
      if (text) parts.push({ text });
      const attachments = pick<Record<string, unknown>[]>(message, "attachments") ?? [];
      for (const att of attachments) {
        parts.push({
          inlineData: {
            mimeType: pick<string>(att, "mimeType", "mime_type") ?? "",
            data: pick<string>(att, "base64Data", "base64_data") ?? "",
          },
        });
      }
    }
    if (parts.length === 0) return acc;
    const last = acc[acc.length - 1] as { role: string; parts: unknown[] } | undefined;
    if (last && last.role === role) {
      (last.parts as unknown[]).push(...parts);
    } else {
      acc.push({ role, parts });
    }
    return acc;
  }, []);

  const requestedMax = pick<number>(body, "maxOutputTokens", "max_output_tokens");
  const maxOutputTokens =
    typeof requestedMax === "number" && requestedMax > 0
      ? Math.floor(requestedMax)
      : maxOutputTokensForModel(model);

  return {
    systemInstruction:
      Array.isArray(systemInstructionParts) && systemInstructionParts.length > 0
        ? { parts: systemInstructionParts }
        : systemPrompt
          ? { parts: [{ text: systemPrompt }] }
          : undefined,
    contents,
    safetySettings: chatSafetySettings(),
    generationConfig: {
      temperature: temperatureFor(model, 0.65),
      topP: 0.95,
      maxOutputTokens,
      thinkingConfig: thinkingConfigFor(
        model,
        pick<Intensity>(body, "thinkingIntensity", "thinking_intensity"),
        pick<boolean>(body, "includeThoughts", "include_thoughts") !== false,
      ),
      enableEnhancedCivicAnswers: String(model || "").startsWith("gemini-3") ? true : undefined,
      mediaResolution: hasImageAttachment(messages) ? "MEDIA_RESOLUTION_HIGH" : undefined,
    },
    tools: toolsFor(body),
  };
}

export function buildTranscriptionRequest(body: Record<string, unknown>, model: string) {
  const systemPrompt = pick<string>(body, "systemPrompt", "system_prompt");
  const prompt = pick<string>(body, "prompt") ?? "";
  const audio = pick<Record<string, unknown>>(body, "audio") ?? {};
  return {
    systemInstruction: systemPrompt ? { parts: [{ text: systemPrompt }] } : undefined,
    contents: [
      {
        role: "user",
        parts: [
          { text: prompt },
          {
            inlineData: {
              mimeType: pick<string>(audio, "mimeType", "mime_type") ?? "",
              data: pick<string>(audio, "base64Data", "base64_data") ?? "",
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: temperatureFor(model, 0.1),
      topP: 0.95,
      maxOutputTokens: 5120,
    },
  };
}

const MEMORY_SYSTEM = `
You maintain compressed conversation memory for AIChat.
Return strict JSON only. Do not answer the user.
Prefer concise Chinese phrasing when the source conversation is Chinese.
Use this schema exactly:
{
  "kind": "casual|teaching|task",
  "title": "short title",
  "focusNote": "compact focus note",
  "openLoops": ["pending question or next step"],
  "memoryItems": ["stable reusable memory item"],
  "archiveTitle": "short archive title or null",
  "archiveSummary": "archive summary or null",
  "archiveOpenLoops": ["pending loop from archive"]
}
Rules:
- Return valid JSON with double quotes and no markdown fence.
- memoryItems must contain only stable reusable memory, not ephemeral chatter.
- If there is no archive candidate, set archiveTitle and archiveSummary to null and archiveOpenLoops to [].
`.trim();

export function buildMemoryRequest(body: Record<string, unknown>, model: string) {
  const sections: string[] = [];
  sections.push(`Mode hint: ${pick<string>(body, "mode") ?? "casual"}`);
  sections.push(`Conversation title: ${pick<string>(body, "conversationTitle", "conversation_title") ?? "Untitled"}`);

  const focus = pick<Record<string, unknown>>(body, "existingFocusState", "existing_focus_state");
  if (focus) {
    const lines: string[] = [];
    if (focus.kind) lines.push(`kind: ${focus.kind}`);
    if (focus.title) lines.push(`title: ${focus.title}`);
    const focusNote = pick<string>(focus, "focusNote", "focus_note");
    if (focusNote) lines.push(`focusNote: ${focusNote}`);
    const openLoops = pick<string[]>(focus, "openLoops", "open_loops") ?? [];
    if (openLoops.length) lines.push(`openLoops: ${openLoops.join(" | ")}`);
    if (lines.length) sections.push(`Existing focus state:\n${lines.join("\n")}`);
  }

  const existingMemory = pick<string[]>(body, "existingMemoryItems", "existing_memory_items") ?? [];
  if (existingMemory.length) sections.push(`Existing reusable memory:\n${existingMemory.map((x) => `- ${x}`).join("\n")}`);

  const recent = pick<Record<string, unknown>[]>(body, "recentMessages", "recent_messages") ?? [];
  sections.push(
    `Recent messages (newest last):\n${recent.map((m, i) => `[${i + 1}] ${pick<string>(m, "role")}: ${pick<string>(m, "text") ?? ""}`).join("\n")}`,
  );

  const archive = pick<Record<string, unknown>[]>(body, "archiveCandidateMessages", "archive_candidate_messages") ?? [];
  if (archive.length) {
    sections.push(
      `Archive candidate (older stable slice to compress if useful):\n${archive.map((m, i) => `[${i + 1}] ${pick<string>(m, "role")}: ${pick<string>(m, "text") ?? ""}`).join("\n")}`,
    );
  } else {
    sections.push("Archive candidate: none");
  }
  sections.push("Return JSON only.");

  return {
    systemInstruction: { parts: [{ text: MEMORY_SYSTEM }] },
    contents: [{ role: "user", parts: [{ text: sections.join("\n\n") }] }],
    generationConfig: {
      temperature: temperatureFor(model, 0.1),
      topP: 0.9,
      maxOutputTokens: 4096,
      responseMimeType: "application/json",
    },
  };
}
