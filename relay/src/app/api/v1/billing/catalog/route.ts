import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { jsonResponse } from "@/lib/api/error";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const ctx = beginObserve(req, "/api/v1/billing/catalog");
  adoptRequestId(req, ctx);
  const state = await billingStore().snapshot();
  await finishObserve(ctx, { statusCode: 200, level: "info", category: "completed", message: "catalog" });
  return jsonResponse(200, {
    plans: state.plans,
    meteringPolicy: state.policy,
  });
}
