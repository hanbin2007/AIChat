import { authenticate } from "@/lib/auth/bearer";
import { config } from "@/lib/config";
import { generateContent, extractFinishReason, extractTranscript } from "@/lib/gemini/generate";
import { buildTranscriptionRequest } from "@/lib/gemini/request";
import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { transcribeRequestSchema, formatZodIssues } from "@/app/api/v1/_schemas";
import { redactTranscribeBody } from "@/app/api/v1/_schemas/redact";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

const billingBypass = process.env.RELAY_BILLING_BYPASS === "1";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/audio/transcribe");
  adoptRequestId(req, ctx);
  const auth = await authenticate(req);
  if (!auth) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;
  if (!billingBypass && (auth.kind !== "client" || !auth.clientKey)) {
    await finishObserve(ctx, {
      statusCode: 401,
      level: "warning",
      category: "failure",
      message: "Per-device key required for metered endpoints.",
    });
    return errorResponse(401, "Per-device key required for metered endpoints.");
  }
  if (!config.geminiApiKey) {
    await finishObserve(ctx, { statusCode: 503, level: "error", category: "failure", message: "GEMINI_API_KEY missing" });
    return errorResponse(503, "Gemini API key is not configured on this relay.");
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Invalid JSON body" });
    return errorResponse(400, "Invalid JSON body.");
  }
  const parsed = transcribeRequestSchema.safeParse(rawBody);
  if (!parsed.success) {
    await finishObserve(ctx, {
      statusCode: 400,
      level: "error",
      category: "failure",
      message: `Invalid request body: ${formatZodIssues(parsed.error)}`,
    });
    return errorResponse(400, `Invalid request body: ${formatZodIssues(parsed.error)}`);
  }
  const body = parsed.data;
  ctx.requestBody = redactTranscribeBody(body);

  const model = body.model ?? "gemini-3-flash-preview";
  ctx.modelID = model;

  let reservationID: string | undefined;
  if (auth.kind === "client" && auth.clientKey) {
    try {
      const reservation = await billingStore().reserveCredits({
        key: auth.clientKey,
        endpoint: "/api/v1/audio/transcribe",
        modelID: model,
        estimatedInputTokens: 2048,
        audioInput: true,
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

  try {
    const payload = await generateContent(model, buildTranscriptionRequest(body as Record<string, unknown>, model));
    const finishReason = extractFinishReason(payload);
    if (!finishReason) throw new Error("Relay transcription ended before Gemini returned a terminal result.");
    if (finishReason === "MAX_TOKENS") throw new Error("Transcript hit the output limit before completion.");
    if (finishReason !== "STOP") throw new Error(`Relay transcription reported an incomplete finish (${finishReason}).`);
    const text = extractTranscript(payload);
    if (!text) throw new Error("Gemini did not return a usable transcript.");

    ctx.finishReason = finishReason;
    ctx.inputTokens = payload.usageMetadata?.promptTokenCount ?? 0;
    ctx.outputTokens = payload.usageMetadata?.candidatesTokenCount ?? 0;
    ctx.responseSummary = text.slice(0, 280);

    if (reservationID) {
      const settled = await billingStore().settleCredits({
        requestID: reservationID,
        inputTokens: ctx.inputTokens!,
        outputTokens: ctx.outputTokens!,
        searchCount: 0,
        audioInput: true,
        modelID: model,
      });
      ctx.settledCredits = settled.settledCredits;
    }
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "completed", message: `transcribe ${finishReason}` });
    return jsonResponse(200, { text, model });
  } catch (err: unknown) {
    if (reservationID) await billingStore().rollbackReservation(reservationID).catch(() => undefined);
    const status = (err as { statusCode?: number }).statusCode ?? 502;
    await finishObserve(ctx, {
      statusCode: status,
      level: "error",
      category: "failure",
      message: (err as Error).message,
    });
    return errorResponse(status, (err as Error).message);
  }
}
