import http from "node:http";
import { TextDecoder } from "node:util";

const port = Number(process.env.PORT || 8787);
const geminiApiKey = process.env.GEMINI_API_KEY;
const relayBearerToken = process.env.RELAY_BEARER_TOKEN;
const transcriptionMaxOutputTokens = 5120;

if (!geminiApiKey || !relayBearerToken) {
  console.error("Missing GEMINI_API_KEY or RELAY_BEARER_TOKEN.");
  process.exit(1);
}

const decoder = new TextDecoder();

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

function unauthorized(res) {
  sendJson(res, 401, { message: "Unauthorized relay request." });
}

function thinkingConfigFor(model, thinkingIntensity = "balanced", includeThoughts = true) {
  const normalizedIntensity = typeof thinkingIntensity === "string" ? thinkingIntensity : "balanced";

  if (String(model || "").startsWith("gemini-3")) {
    if (String(model || "").startsWith("gemini-3.1-pro") && normalizedIntensity === "extreme") {
      return {
        includeThoughts
      };
    }

    const thinkingLevelByIntensity = {
      fast: "minimal",
      balanced: "medium",
      deep: "high",
      extreme: "high"
    };

    return {
      thinkingLevel: thinkingLevelByIntensity[normalizedIntensity] || "medium",
      includeThoughts
    };
  }

  const thinkingBudgetByIntensity = {
    fast: 0,
    balanced: 8192,
    deep: 24576,
    extreme: -1
  };

  return {
    thinkingBudget: thinkingBudgetByIntensity[normalizedIntensity] ?? 8192,
    includeThoughts
  };
}

function maxOutputTokensForModel(model = "") {
  if (String(model).startsWith("gemini-3") || String(model).startsWith("gemini-2.5")) {
    return 65536;
  }

  return 8192;
}

function temperatureForModel(model, fallbackTemperature) {
  return String(model || "").startsWith("gemini-3") ? 1 : fallbackTemperature;
}

function toGeminiRequest(body, model) {
  return {
    systemInstruction: body.systemPrompt
      ? {
          parts: [{ text: body.systemPrompt }]
        }
      : undefined,
    contents: body.messages.map((message) => {
      const parts = [];

      if (message.text) {
        parts.push({ text: message.text });
      }

      for (const attachment of message.attachments || []) {
        parts.push({
          inlineData: {
            mimeType: attachment.mimeType,
            data: attachment.base64Data
          }
        });
      }

      return {
        role: message.role === "assistant" ? "model" : "user",
        parts
      };
    }),
    generationConfig: {
      temperature: temperatureForModel(model, 0.65),
      topP: 0.9,
      maxOutputTokens:
        Number.isFinite(body.maxOutputTokens) && body.maxOutputTokens > 0
          ? Math.floor(body.maxOutputTokens)
          : maxOutputTokensForModel(model),
      thinkingConfig: thinkingConfigFor(model, body.thinkingIntensity, body.includeThoughts !== false)
    }
  };
}

function toGeminiTranscriptionRequest(body, model) {
  return {
    systemInstruction: body.systemPrompt
      ? {
          parts: [{ text: body.systemPrompt }]
        }
      : undefined,
    contents: [
      {
        role: "user",
        parts: [
          { text: body.prompt || "" },
          {
            inlineData: {
              mimeType: body.audio?.mimeType || "",
              data: body.audio?.base64Data || ""
            }
          }
        ]
      }
    ],
    generationConfig: {
      temperature: temperatureForModel(model, 0.1),
      topP: 0.95,
      maxOutputTokens: transcriptionMaxOutputTokens
    }
  };
}

const memoryExtractionSystemPrompt = `
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

function memoryExtractionPrompt(body) {
  const sections = [
    `Mode hint: ${body.mode || "casual"}`,
    `Conversation title: ${body.conversationTitle || "Untitled"}`
  ];

  if (body.existingFocusState) {
    const focusLines = [];
    if (body.existingFocusState.kind) {
      focusLines.push(`kind: ${body.existingFocusState.kind}`);
    }
    if (body.existingFocusState.title) {
      focusLines.push(`title: ${body.existingFocusState.title}`);
    }
    if (body.existingFocusState.focusNote) {
      focusLines.push(`focusNote: ${body.existingFocusState.focusNote}`);
    }
    if ((body.existingFocusState.openLoops || []).length > 0) {
      focusLines.push(`openLoops: ${body.existingFocusState.openLoops.join(" | ")}`);
    }
    if (focusLines.length > 0) {
      sections.push(`Existing focus state:\n${focusLines.join("\n")}`);
    }
  }

  if ((body.existingMemoryItems || []).length > 0) {
    sections.push(`Existing reusable memory:\n${body.existingMemoryItems.map((item) => `- ${item}`).join("\n")}`);
  }

  sections.push(
    `Recent messages (newest last):\n${(body.recentMessages || [])
      .map((message, index) => `[${index + 1}] ${message.role}: ${message.text || ""}`)
      .join("\n")}`
  );

  if ((body.archiveCandidateMessages || []).length > 0) {
    sections.push(
      `Archive candidate (older stable slice to compress if useful):\n${body.archiveCandidateMessages
        .map((message, index) => `[${index + 1}] ${message.role}: ${message.text || ""}`)
        .join("\n")}`
    );
  } else {
    sections.push("Archive candidate: none");
  }

  sections.push("Return JSON only.");
  return sections.join("\n\n");
}

function toGeminiMemoryRequest(body, model) {
  return {
    systemInstruction: {
      parts: [{ text: memoryExtractionSystemPrompt }]
    },
    contents: [
      {
        role: "user",
        parts: [{ text: memoryExtractionPrompt(body) }]
      }
    ],
    generationConfig: {
      temperature: temperatureForModel(model, 0.1),
      topP: 0.9,
      maxOutputTokens: 4096,
      responseMimeType: "application/json"
    }
  };
}

function extractChunkParts(chunk) {
  const candidate = chunk?.candidates?.[0];
  const parts = candidate?.content?.parts || [];
  const answerText = parts
    .filter((part) => part.thought !== true)
    .map((part) => part.text || "")
    .join("\n")
    .trim();
  const thoughtText = parts
    .filter((part) => part.thought === true)
    .map((part) => part.text || "")
    .join("\n")
    .trim();

  return {
    answerText,
    thoughtText,
    finishReason: typeof candidate?.finishReason === "string" ? candidate.finishReason.trim() : ""
  };
}

function normalizedDelta(chunkText, emittedText) {
  if (!chunkText) {
    return { delta: "", emittedText };
  }

  if (chunkText.startsWith(emittedText)) {
    return {
      delta: chunkText.slice(emittedText.length),
      emittedText: chunkText
    };
  }

  if (emittedText.startsWith(chunkText)) {
    return {
      delta: "",
      emittedText
    };
  }

  return {
    delta: chunkText,
    emittedText: emittedText + chunkText
  };
}

function makeRelayError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function extractTranscript(payload) {
  const parts = payload?.candidates?.[0]?.content?.parts || [];

  return parts
    .filter((part) => part.thought !== true)
    .map((part) => part.text || "")
    .join("\n")
    .replace(/\s+/g, " ")
    .trim();
}

function decodeMemoryExtractionPayload(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) {
    throw makeRelayError(502, "Gemini did not return memory extraction JSON.");
  }

  try {
    return JSON.parse(trimmed);
  } catch {}

  const match = trimmed.match(/\{[\s\S]*\}/);
  if (!match) {
    throw makeRelayError(502, "Gemini returned invalid memory extraction JSON.");
  }

  return JSON.parse(match[0]);
}

async function transcribeGeminiResponse({ model, requestBody }) {
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": geminiApiKey
      },
      body: JSON.stringify(requestBody)
    }
  );

  if (!geminiResponse.ok) {
    const errorText = await geminiResponse.text();
    throw makeRelayError(geminiResponse.status, errorText || "Gemini relay failed.");
  }

  const payload = await geminiResponse.json();
  const finishReason = String(payload?.candidates?.[0]?.finishReason || "").trim().toUpperCase();

  if (!finishReason) {
    throw makeRelayError(502, "Relay transcription ended before Gemini returned a terminal result.");
  }

  if (finishReason === "MAX_TOKENS") {
    throw makeRelayError(502, "Transcript hit the output limit before completion.");
  }

  if (finishReason !== "STOP") {
    throw makeRelayError(502, `Relay transcription reported an incomplete finish (${finishReason}).`);
  }

  const transcript = extractTranscript(payload);
  if (!transcript) {
    throw makeRelayError(502, "Gemini did not return a usable transcript.");
  }

  return {
    text: transcript,
    model
  };
}

async function extractMemoryGeminiResponse({ model, requestBody }) {
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": geminiApiKey
      },
      body: JSON.stringify(requestBody)
    }
  );

  if (!geminiResponse.ok) {
    const errorText = await geminiResponse.text();
    throw makeRelayError(geminiResponse.status, errorText || "Gemini relay failed.");
  }

  const payload = await geminiResponse.json();
  const finishReason = String(payload?.candidates?.[0]?.finishReason || "").trim().toUpperCase();

  if (!finishReason) {
    throw makeRelayError(502, "Relay memory extraction ended before Gemini returned a terminal result.");
  }

  if (finishReason === "MAX_TOKENS") {
    throw makeRelayError(502, "Memory extraction hit the output limit before completion.");
  }

  if (finishReason !== "STOP") {
    throw makeRelayError(502, `Relay memory extraction reported an incomplete finish (${finishReason}).`);
  }

  return decodeMemoryExtractionPayload(extractTranscript(payload));
}

async function streamGeminiResponse({ model, requestBody, res }) {
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "x-goog-api-key": geminiApiKey
      },
      body: JSON.stringify(requestBody)
    }
  );

  if (!geminiResponse.ok) {
    const errorText = await geminiResponse.text();
    sendJson(res, geminiResponse.status, { message: errorText || "Gemini relay failed." });
    return;
  }

  res.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    "Connection": "keep-alive"
  });

  let buffered = "";
  let emittedAnswerText = "";
  let emittedThoughtText = "";
  let finishReason = "";

  for await (const chunk of geminiResponse.body) {
    buffered += decoder.decode(chunk, { stream: true });
    const lines = buffered.split("\n");
    buffered = lines.pop() || "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) {
        continue;
      }

      const payload = trimmed.slice(5).trim();
      if (!payload || payload === "[DONE]") {
        continue;
      }

      let parsed;
      try {
        parsed = JSON.parse(payload);
      } catch {
        continue;
      }

      const { answerText, thoughtText, finishReason: chunkFinishReason } = extractChunkParts(parsed);
      if (chunkFinishReason) {
        finishReason = chunkFinishReason;
      }

      if (thoughtText) {
        const result = normalizedDelta(thoughtText, emittedThoughtText);
        emittedThoughtText = result.emittedText;

        if (result.delta) {
          res.write(`event: thought_delta\n`);
          res.write(`data: ${JSON.stringify({ type: "thought_delta", text: result.delta })}\n\n`);
        }
      }

      if (answerText) {
        const result = normalizedDelta(answerText, emittedAnswerText);
        emittedAnswerText = result.emittedText;

        if (result.delta) {
          res.write(`event: answer_delta\n`);
          res.write(`data: ${JSON.stringify({ type: "answer_delta", text: result.delta })}\n\n`);
        }
      }
    }
  }

  buffered += decoder.decode();
  if (buffered.trim()) {
    const trimmed = buffered.trim();
    if (trimmed.startsWith("data:")) {
      const payload = trimmed.slice(5).trim();
      if (payload && payload !== "[DONE]") {
        try {
          const parsed = JSON.parse(payload);
          const { answerText, thoughtText, finishReason: chunkFinishReason } = extractChunkParts(parsed);
          if (chunkFinishReason) {
            finishReason = chunkFinishReason;
          }

          if (thoughtText) {
            const result = normalizedDelta(thoughtText, emittedThoughtText);
            emittedThoughtText = result.emittedText;

            if (result.delta) {
              res.write(`event: thought_delta\n`);
              res.write(`data: ${JSON.stringify({ type: "thought_delta", text: result.delta })}\n\n`);
            }
          }

          if (answerText) {
            const result = normalizedDelta(answerText, emittedAnswerText);
            emittedAnswerText = result.emittedText;

            if (result.delta) {
              res.write(`event: answer_delta\n`);
              res.write(`data: ${JSON.stringify({ type: "answer_delta", text: result.delta })}\n\n`);
            }
          }
        } catch {
          // Ignore an incomplete tail chunk; completion is validated below.
        }
      }
    }
  }

  if (!finishReason) {
    res.write(`event: error\n`);
    res.write(
      `data: ${JSON.stringify({ type: "error", message: "Relay stream ended before Gemini sent a terminal chunk." })}\n\n`
    );
    res.end();
    return;
  }

  res.write(`event: done\n`);
  res.write(`data: ${JSON.stringify({ type: "done", finishReason })}\n\n`);
  res.end();
}

function writeRelayStreamError(res, message) {
  if (res.writableEnded) {
    return;
  }

  if (res.headersSent) {
    res.write(`event: error\n`);
    res.write(`data: ${JSON.stringify({ type: "error", message })}\n\n`);
    res.end();
    return;
  }

  sendJson(res, 502, { message });
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method !== "POST") {
    sendJson(res, 404, { message: "Not found." });
    return;
  }

  if (req.url !== "/v1/chat/stream" && req.url !== "/v1/audio/transcribe" && req.url !== "/v1/memory/extract") {
    sendJson(res, 404, { message: "Not found." });
    return;
  }

  const authHeader = req.headers.authorization || "";
  if (authHeader !== `Bearer ${relayBearerToken}`) {
    unauthorized(res);
    return;
  }

  let rawBody = "";
  for await (const chunk of req) {
    rawBody += chunk;
  }

  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    sendJson(res, 400, { message: "Invalid JSON body." });
    return;
  }

  if (req.url === "/v1/chat/stream") {
    try {
      const model = body.model || "gemini-3-flash-preview";
      await streamGeminiResponse({
        model,
        requestBody: toGeminiRequest(body, model),
        res
      });
    } catch (error) {
      writeRelayStreamError(res, error instanceof Error ? error.message : "Relay error.");
    }
    return;
  }

  if (req.url === "/v1/memory/extract") {
    try {
      const model = body.model || "gemini-3-flash-preview";
      const response = await extractMemoryGeminiResponse({
        model,
        requestBody: toGeminiMemoryRequest(body, model)
      });
      sendJson(res, 200, response);
    } catch (error) {
      const statusCode = typeof error?.statusCode === "number" ? error.statusCode : 502;
      const message = error instanceof Error ? error.message : "Relay error.";
      sendJson(res, statusCode, { message });
    }
    return;
  }

  try {
    const model = body.model || "gemini-3-flash-preview";
    const response = await transcribeGeminiResponse({
      model,
      requestBody: toGeminiTranscriptionRequest(body, model)
    });
    sendJson(res, 200, response);
  } catch (error) {
    const statusCode = typeof error?.statusCode === "number" ? error.statusCode : 502;
    const message = error instanceof Error ? error.message : "Relay error.";
    sendJson(res, statusCode, { message });
  }
});

server.listen(port, () => {
  console.log(`AIChat relay listening on http://127.0.0.1:${port}`);
});
