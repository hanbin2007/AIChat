import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { pick } from "@/lib/gemini/dual-key";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/billing/purchase/prepare");
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
  const requestedAccountID = auth.clientKey?.accountID ?? pick<string>(body, "accountID", "account_id");
  const { accountID, appAccountToken } = await billingStore().preparePurchase({
    accountID: requestedAccountID,
  });
  await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "purchase prepared" });
  // CONTRACT: return BOTH accountID and appAccountToken. Client treats
  // accountID as optional / unused (forward-compat).
  return jsonResponse(200, { accountID: accountID ?? requestedAccountID, appAccountToken });
}
