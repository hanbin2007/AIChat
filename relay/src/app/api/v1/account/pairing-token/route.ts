import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { pick } from "@/lib/gemini/dual-key";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/account/pairing-token");
  const auth = await authenticate(req);
  if (!auth?.clientKey) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;
  let body: Record<string, unknown> = {};
  try {
    body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  } catch { /* empty body is allowed */ }
  const deviceID = auth.clientKey.deviceID ?? pick<string>(body, "deviceID", "device_id") ?? "unknown";
  const token = await billingStore().issuePairingToken({ accountID: auth.clientKey.accountID, deviceID });
  await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "pairing token issued" });
  return jsonResponse(200, { pairingToken: token.token, expiresAt: token.expiresAt });
}
