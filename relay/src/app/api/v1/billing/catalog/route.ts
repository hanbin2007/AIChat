import { billingStore } from "@/lib/store/billing-store";
import { jsonResponse } from "@/lib/api/error";
import type { MeteringPolicy } from "@/lib/billing/types";

export const runtime = "nodejs";

/**
 * Public projection of the metering policy. The catalog endpoint is
 * unauthenticated, so it must not leak internal economics: the cost basis
 * (`creditBudgetUSDPer1000Credits`) and the internal device cap
 * (`maxBoundDevices`) are zeroed out. The client decoder requires these keys
 * to be present (non-optional), so the shape is preserved while the sensitive
 * values are withheld. The per-model `rates` and trial parameters are part of
 * the customer-facing pricing surface and are kept.
 */
function publicMeteringPolicy(policy: MeteringPolicy): MeteringPolicy {
  return {
    creditBudgetUSDPer1000Credits: 0,
    trialCredits: policy.trialCredits,
    trialDurationDays: policy.trialDurationDays,
    lowBalanceThresholdCredits: policy.lowBalanceThresholdCredits,
    maxBoundDevices: 0,
    creditMultiplier: policy.creditMultiplier,
    rates: policy.rates,
  };
}

export async function GET() {
  const state = await billingStore().snapshot();
  return jsonResponse(200, {
    plans: state.plans,
    meteringPolicy: publicMeteringPolicy(state.policy),
  });
}
