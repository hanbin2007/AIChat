import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { purchasePrepareRequestSchema } from "@/app/api/v1/_schemas";
import { redactBillingBody } from "@/app/api/v1/_schemas/redact";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/billing/purchase/prepare");
  adoptRequestId(req, ctx);
  const auth = await authenticate(req);
  if (!auth) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;
  let rawBody: unknown = {};
  try {
    rawBody = await req.json();
  } catch {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Invalid JSON body" });
    return errorResponse(400, "Invalid JSON body.");
  }
  ctx.requestBody = redactBillingBody(rawBody);
  const parsed = purchasePrepareRequestSchema.safeParse(rawBody);
  const body = parsed.success ? parsed.data : { accountID: undefined };
  const accountID = auth.clientKey?.accountID ?? body.accountID;
  const { appAccountToken } = await billingStore().preparePurchase({ accountID });
  await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "purchase prepared" });
  return jsonResponse(200, { appAccountToken });
}
