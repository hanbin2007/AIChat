import { billingStore } from "@/lib/store/billing-store";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET() {
  const state = await billingStore().snapshot();
  return jsonResponse(200, {
    plans: state.plans,
    meteringPolicy: state.policy,
  });
}
