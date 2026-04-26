/**
 * Per-route request body redaction. Drops base64 audio / image bodies and
 * full conversation text from the activity log so the on-disk
 * `request-log.json` doesn't carry user-private payloads.
 *
 * TODO(A2): consolidate into `lib/api/observe.ts` once Agent A2 lands.
 */

export function redactChatBody(body: unknown): unknown {
  const obj = body as Record<string, unknown> | undefined;
  if (!obj) return undefined;
  const messages = Array.isArray(obj.messages) ? (obj.messages as Record<string, unknown>[]) : [];
  return {
    model: obj.model,
    thinkingIntensity: obj.thinkingIntensity,
    maxOutputTokens: obj.maxOutputTokens,
    includeThoughts: obj.includeThoughts,
    usesGoogleSearch: obj.usesGoogleSearch,
    usesCodeExecution: obj.usesCodeExecution,
    systemPromptCharCount: typeof obj.systemPrompt === "string" ? (obj.systemPrompt as string).length : 0,
    messageCount: messages.length,
    messageCharCount: messages.reduce(
      (sum, m) => sum + (typeof m.text === "string" ? (m.text as string).length : 0),
      0,
    ),
    attachmentCount: messages.reduce((sum, m) => {
      const atts = Array.isArray(m.attachments) ? (m.attachments as unknown[]).length : 0;
      return sum + atts;
    }, 0),
  };
}

export function redactTranscribeBody(body: unknown): unknown {
  const obj = body as Record<string, unknown> | undefined;
  if (!obj) return undefined;
  const audio = (obj.audio ?? {}) as Record<string, unknown>;
  const base64 = typeof audio.base64Data === "string" ? (audio.base64Data as string) : "";
  return {
    model: obj.model,
    promptCharCount: typeof obj.prompt === "string" ? (obj.prompt as string).length : 0,
    audio: {
      mimeType: audio.mimeType,
      base64Length: base64.length,
      filename: audio.filename,
    },
  };
}

export function redactMemoryBody(body: unknown): unknown {
  const obj = body as Record<string, unknown> | undefined;
  if (!obj) return undefined;
  const recent = Array.isArray(obj.recentMessages) ? (obj.recentMessages as Record<string, unknown>[]) : [];
  const archive = Array.isArray(obj.archiveCandidateMessages)
    ? (obj.archiveCandidateMessages as Record<string, unknown>[])
    : [];
  const totalChars = [...recent, ...archive].reduce(
    (sum, m) => sum + (typeof m.text === "string" ? (m.text as string).length : 0),
    0,
  );
  return {
    model: obj.model,
    mode: obj.mode,
    conversationTitle: obj.conversationTitle,
    messageCount: recent.length + archive.length,
    charCount: totalChars,
  };
}

export function redactBillingBody(body: unknown): unknown {
  const obj = body as Record<string, unknown> | undefined;
  if (!obj) return undefined;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === "string" && v.length > 256) {
      out[k] = `[len=${v.length}]`;
    } else if (k === "transaction" || k === "transactions") {
      out[k] = "[redacted]";
    } else {
      out[k] = v;
    }
  }
  return out;
}
