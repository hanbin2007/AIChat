import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { joinPairedRequestSchema, formatZodIssues } from "@/app/api/v1/_schemas";
import { redactBillingBody } from "@/app/api/v1/_schemas/redact";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/account/join-paired");
  adoptRequestId(req, ctx);
  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Invalid JSON body" });
    return errorResponse(400, "Invalid JSON body.");
  }
  ctx.requestBody = redactBillingBody(rawBody);
  const parsed = joinPairedRequestSchema.safeParse(rawBody);
  if (!parsed.success) {
    const message = formatZodIssues(parsed.error);
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message });
    return errorResponse(400, message);
  }
  const body = parsed.data;

  try {
    const result = await billingStore().joinPaired({
      pairingToken: body.pairingToken,
      deviceID: body.deviceID,
      platform: body.platform,
      deviceAlias: body.deviceAlias,
    });
    const status = await billingStore().getAccountStatus(result.key);
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "device paired" });
    return jsonResponse(200, status);
  } catch (err) {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: (err as Error).message });
    return errorResponse(400, (err as Error).message);
  }
}
