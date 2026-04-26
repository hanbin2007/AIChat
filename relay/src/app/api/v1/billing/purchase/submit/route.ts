import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { pick } from "@/lib/gemini/dual-key";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { DevicePlatform } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/billing/purchase/submit");
  const auth = await authenticate(req);
  if (!auth) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return errorResponse(400, "Invalid JSON body.");
  }
  const transaction = pick<Record<string, unknown>>(body, "transaction") ?? body;
  const signedTransactionInfo =
    pick<string>(transaction, "signedTransactionInfo", "signed_transaction_info") ??
    pick<string>(body, "signedTransactionInfo", "signed_transaction_info");
  if (!signedTransactionInfo) {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Missing signed transaction" });
    return errorResponse(400, "Missing signedTransactionInfo.");
  }
  const accountID = auth.clientKey?.accountID ?? pick<string>(body, "accountID", "account_id");
  const deviceID = auth.clientKey?.deviceID ?? pick<string>(body, "deviceID", "device_id");
  const platform = (pick<string>(body, "platform") as DevicePlatform) ?? "unknown";

  try {
    await billingStore().submitPurchase({ signedTransactionInfo, accountID, deviceID, platform });
    const snapshot = auth.clientKey
      ? await billingStore().getAccountStatus(auth.clientKey)
      : null;
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "purchase submitted" });
    return jsonResponse(200, snapshot ?? { ok: true });
  } catch (err) {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: (err as Error).message });
    return errorResponse(400, (err as Error).message);
  }
}
