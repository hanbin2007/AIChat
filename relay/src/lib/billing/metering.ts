import type { MeteringPolicy, MeteringRate } from "./types";

/**
 * Derive a coarse pricing family key from a model ID, e.g.
 *   "gemini-3.1-pro-preview"  → "gemini-3-pro"
 *   "gemini-3-flash-preview"  → "gemini-3-flash"
 *   "gemini-2.5-flash"        → "gemini-2-flash"
 * The major version is collapsed (3.1 → 3) so a point release can't be
 * mis-mapped to a different tier, and the tier word (pro/flash/lite) is
 * matched explicitly rather than by raw prefix.
 */
function familyKey(modelID: string): string | undefined {
  const lower = modelID.toLowerCase();
  const versionMatch = lower.match(/gemini-(\d+)/);
  if (!versionMatch) return undefined;
  const major = versionMatch[1];
  const tier = ["pro", "flash-lite", "lite", "flash"].find((t) => lower.includes(t));
  if (!tier) return undefined;
  // Normalise flash-lite/lite to a single "lite" bucket.
  const normalisedTier = tier === "flash-lite" ? "lite" : tier;
  return `gemini-${major}-${normalisedTier}`;
}

/**
 * Resolve the metering rate for a model. Exact match first, then a coarse
 * version+tier family match. Unknown models DO NOT fall back to the most
 * expensive rate — they resolve to the cheapest available rate so a typo or a
 * newly-launched model can never silently overcharge.
 */
export function rateForModel(policy: MeteringPolicy, modelID: string | undefined): MeteringRate {
  if (modelID) {
    const exact = policy.rates.find((r) => r.modelID === modelID);
    if (exact) return exact;
    const wantFamily = familyKey(modelID);
    if (wantFamily) {
      const family = policy.rates.find((r) => familyKey(r.modelID) === wantFamily);
      if (family) return family;
    }
  }
  // Safe default: cheapest rate by output cost (flash-tier), never the pro rate.
  return policy.rates.reduce((cheapest, r) =>
    r.outputCreditsPerMillion < cheapest.outputCreditsPerMillion ? r : cheapest,
  );
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
