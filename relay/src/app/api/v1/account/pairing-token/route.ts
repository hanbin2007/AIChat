import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { pairingTokenRequestSchema } from "@/app/api/v1/_schemas";
import { redactBillingBody } from "@/app/api/v1/_schemas/redact";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/account/pairing-token");
  adoptRequestId(req, ctx);
  const auth = await authenticate(req);
  if (!auth?.clientKey) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;

  let rawBody: unknown = {};
  try {
    rawBody = (await req.json().catch(() => ({}))) as unknown;
  } catch {
    /* empty body is allowed */
  }
  const parsed = pairingTokenRequestSchema.safeParse(rawBody);
  const body = parsed.success ? parsed.data : { deviceID: undefined };
  ctx.requestBody = redactBillingBody(rawBody);

  const deviceID = auth.clientKey.deviceID ?? body.deviceID ?? "unknown";
  const token = await billingStore().issuePairingToken({
    accountID: auth.clientKey.accountID,
    deviceID,
  });
  await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "pairing token issued" });
  return jsonResponse(200, { pairingToken: token.token, expiresAt: token.expiresAt });
}
