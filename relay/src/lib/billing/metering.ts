import type { MeteringPolicy, MeteringRate } from "./types";

/**
 * Credit calculation — mirrors `RelayBillingStore.creditsForUsage` in
 * `AIChat Relay/RelayBillingStore.swift`. Unknown models fall back to the
 * first rate entry; callers should guard against that.
 */
export function rateForModel(policy: MeteringPolicy, modelID: string | undefined): MeteringRate {
  if (modelID) {
    const exact = policy.rates.find((r) => r.modelID === modelID);
    if (exact) return exact;
    const family = policy.rates.find((r) => modelID.startsWith(r.modelID.split("-").slice(0, 2).join("-")));
    if (family) return family;
  }
  return policy.rates[0];
}

export interface UsageInput {
  inputTokens: number;
  outputTokens: number;
  searchCount: number;
  audioInput: boolean;
}

export function creditsForUsage(
  policy: MeteringPolicy,
  rate: MeteringRate,
  usage: UsageInput,
): number {
  const inputEffective = usage.audioInput
    ? (rate.audioInputCreditsPerMillion ?? rate.inputCreditsPerMillion)
    : usage.inputTokens > 200_000 && rate.inputCreditsPerMillionOver200k
      ? rate.inputCreditsPerMillionOver200k
      : rate.inputCreditsPerMillion;
  const outputEffective =
    usage.outputTokens > 200_000 && rate.outputCreditsPerMillionOver200k
      ? rate.outputCreditsPerMillionOver200k
      : rate.outputCreditsPerMillion;
  const raw =
    (usage.inputTokens / 1_000_000) * inputEffective +
    (usage.outputTokens / 1_000_000) * outputEffective +
    usage.searchCount * rate.searchSurchargeCredits;
  const credits = Math.ceil(raw * policy.creditMultiplier);
  return Math.max(credits, 1);
}

/** Default upper bound on output tokens, used for pre-reservation. */
export function maxOutputTokensForModel(modelID: string | undefined): number {
  if (!modelID) return 8192;
  if (modelID.startsWith("gemini-3") || modelID.startsWith("gemini-2.5")) return 65536;
  return 8192;
}
