import { authenticate } from "@/lib/auth/bearer";
import { config } from "@/lib/config";
import { buildChatRequest } from "@/lib/gemini/request";
import { proxyGeminiStream } from "@/lib/gemini/stream";
import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse } from "@/lib/api/error";

export const runtime = "nodejs";
export const maxDuration = 300;

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/chat/stream");
  const auth = await authenticate(req);
  if (!auth) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;
  ctx.conversationID = req.headers.get("x-aichat-conversation-id") ?? undefined;

  if (!config.geminiApiKey) {
    await finishObserve(ctx, { statusCode: 503, level: "error", category: "failure", message: "GEMINI_API_KEY missing" });
    return errorResponse(503, "Gemini API key is not configured on this relay.");
  }

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Invalid JSON body" });
    return errorResponse(400, "Invalid JSON body.");
  }
  ctx.requestBody = body;
  const model = typeof body.model === "string" ? body.model : "gemini-3-flash-preview";
  ctx.modelID = model;
  const requestBody = buildChatRequest(body, model);

  // Pre-reservation (client-key calls only).
  let reservationID: string | undefined;
  if (auth.kind === "client" && auth.clientKey) {
    try {
      const estimatedInputTokens = estimateInputTokens(body);
      const reservation = await billingStore().reserveCredits({
        key: auth.clientKey,
        endpoint: "/api/v1/chat/stream",
        modelID: model,
        estimatedInputTokens,
        audioInput: false,
      });
      reservationID = reservation.requestID;
      ctx.reservedCredits = reservation.reservedCredits;
    } catch (err: unknown) {
      const status = (err as { statusCode?: number }).statusCode ?? 402;
      await finishObserve(ctx, {
        statusCode: status,
        level: "warning",
        category: "billing",
        message: (err as Error).message,
      });
      return errorResponse(status, (err as Error).message);
    }
  }

  const encoder = new TextEncoder();
  let aborted = false;
  const stream = new ReadableStream({
    async start(controller) {
      const send = (event: string, data: Record<string, unknown>) => {
        if (aborted) return;
        try {
          controller.enqueue(encoder.encode(`event: ${event}\n`));
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
        } catch {
          aborted = true;
        }
      };
      let mergedAnswer = "";
      let mergedThought = "";
      let finishReason = "";
      let inputTokens = 0;
      let outputTokens = 0;
      let searchQueryCount = 0;
      // Client disconnect → release reservation so credits don't leak.
      const signal = req.signal;
      const onAbort = async () => {
        if (aborted) return;
        aborted = true;
        if (reservationID) await billingStore().rollbackReservation(reservationID).catch(() => undefined);
        try { controller.close(); } catch { /* already closed */ }
        await finishObserve(ctx, {
          statusCode: 499,
          level: "warning",
          category: "failure",
          message: "client disconnected before completion",
          mergedAnswer,
          mergedThought,
        });
      };
      signal.addEventListener("abort", onAbort, { once: true });

      try {
        const result = await proxyGeminiStream({
          model,
          requestBody,
          onEvent: (event, data) => {
            if (event === "answer_delta" && typeof data.text === "string") mergedAnswer += data.text;
            if (event === "thought_delta" && typeof data.text === "string") mergedThought += data.text;
            if (event === "done" && typeof data.finishReason === "string") finishReason = data.finishReason;
            send(event, data);
          },
        });
        finishReason = result.finishReason;
        inputTokens = result.usage?.promptTokens ?? 0;
        outputTokens = result.usage?.candidatesTokens ?? 0;
        searchQueryCount = result.searchQueryCount;
      } catch (err: unknown) {
        if (aborted) return;
        send("error", { type: "error", message: (err as Error).message });
        if (reservationID) await billingStore().rollbackReservation(reservationID).catch(() => undefined);
        controller.close();
        await finishObserve(ctx, {
          statusCode: 502,
          level: "error",
          category: "failure",
          message: (err as Error).message,
          mergedAnswer,
          mergedThought,
        });
        return;
      } finally {
        signal.removeEventListener("abort", onAbort);
      }
      if (aborted) return;
      controller.close();
      ctx.finishReason = finishReason;
      ctx.inputTokens = inputTokens;
      ctx.outputTokens = outputTokens;
      ctx.responseSummary = mergedAnswer.slice(0, 280);
      if (reservationID) {
        const hasSearchTool = (requestBody as { tools?: { google_search?: unknown }[] }).tools?.some(
          (t) => "google_search" in t,
        )
          ? true
          : false;
        // Prefer the real grounded-search count from groundingMetadata. For
        // gemini-3.x each query is billed individually; for 2.5-era a request
        // is billed as a single search surcharge regardless of query count.
        // When grounding metadata is absent (searchQueryCount === 0) fall back
        // to tool presence so the legacy contract still holds.
        let searchCount: number;
        if (searchQueryCount > 0) {
          searchCount = model.startsWith("gemini-3") ? searchQueryCount : 1;
        } else {
          searchCount = hasSearchTool ? 1 : 0;
        }
        const settled = await billingStore().settleCredits({
          requestID: reservationID,
          inputTokens,
          outputTokens,
          searchCount,
          audioInput: false,
          modelID: model,
        });
        ctx.settledCredits = settled.settledCredits;
      }
      await finishObserve(ctx, {
        statusCode: 200,
        level: "success",
        category: "completed",
        message: `chat ${finishReason}`,
        mergedAnswer,
        mergedThought,
      });
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Request-Id": ctx.requestID,
    },
  });
}

function estimateInputTokens(body: Record<string, unknown>): number {
  // Crude 4-char-per-token estimate — pre-reservation is refunded on settle.
  const messages = Array.isArray(body.messages) ? (body.messages as Record<string, unknown>[]) : [];
  let chars = 0;
  for (const m of messages) chars += String(m.text ?? "").length;
  if (typeof body.systemPrompt === "string") chars += body.systemPrompt.length;
  return Math.max(64, Math.ceil(chars / 4));
}
