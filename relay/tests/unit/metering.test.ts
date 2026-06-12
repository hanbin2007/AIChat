import { describe, expect, it } from "vitest";
import { creditsForUsage, maxOutputTokensForModel, rateForModel } from "@/lib/billing/metering";
import { DEFAULT_POLICY } from "@/lib/billing/defaults";

describe("rateForModel", () => {
  const cheapest = DEFAULT_POLICY.rates.reduce((c, r) =>
    r.outputCreditsPerMillion < c.outputCreditsPerMillion ? r : c,
  );

  it("returns the exact match when present", () => {
    expect(rateForModel(DEFAULT_POLICY, "gemini-3-flash-preview").modelID).toBe("gemini-3-flash-preview");
    expect(rateForModel(DEFAULT_POLICY, "gemini-3.1-pro-preview").modelID).toBe("gemini-3.1-pro-preview");
  });

  it("resolves a point release to its version+tier family rather than pro", () => {
    // gemini-3.5-flash-preview has no exact entry but must map to the flash
    // family — never to the (more expensive) pro rate.
    const rate = rateForModel(DEFAULT_POLICY, "gemini-3.5-flash-preview");
    expect(rate.modelID).toBe("gemini-3-flash-preview");
  });

  it("does NOT fall back to the most expensive pro rate for unknown models", () => {
    const rate = rateForModel(DEFAULT_POLICY, "made-up-model");
    expect(rate.modelID).toBe(cheapest.modelID);
    expect(rate.outputCreditsPerMillion).toBeLessThanOrEqual(
      DEFAULT_POLICY.rates[0].outputCreditsPerMillion,
    );
  });

  it("falls back to the cheapest rate when modelID is undefined", () => {
    expect(rateForModel(DEFAULT_POLICY, undefined).modelID).toBe(cheapest.modelID);
  });
});

describe("creditsForUsage", () => {
  it("minimum credit is always 1", () => {
    const rate = DEFAULT_POLICY.rates[0];
    expect(
      creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 0, outputTokens: 0, searchCount: 0, audioInput: false }),
    ).toBe(1);
  });

  it("applies the over-200k tier for inputs > 200 000 tokens", () => {
    const rate = DEFAULT_POLICY.rates.find((r) => r.inputCreditsPerMillionOver200k)!;
    const low = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 100_000, outputTokens: 0, searchCount: 0, audioInput: false });
    const high = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 300_000, outputTokens: 0, searchCount: 0, audioInput: false });
    expect(high).toBeGreaterThan(low);
    // The >200k tier is at least 2x the standard in default policy.
    expect(high).toBeGreaterThan(low * 2);
  });

  it("applies the audio rate instead of the input rate when audioInput=true", () => {
    const rate = DEFAULT_POLICY.rates.find((r) => r.audioInputCreditsPerMillion)!;
    const textCost = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 100_000, outputTokens: 0, searchCount: 0, audioInput: false });
    const audioCost = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 100_000, outputTokens: 0, searchCount: 0, audioInput: true });
    expect(audioCost).not.toBe(textCost);
  });

  it("adds searchSurcharge * searchCount", () => {
    const rate = DEFAULT_POLICY.rates[0];
    const base = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 1_000_000, outputTokens: 1_000_000, searchCount: 0, audioInput: false });
    const withSearch = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 1_000_000, outputTokens: 1_000_000, searchCount: 3, audioInput: false });
    expect(withSearch - base).toBe(Math.ceil(3 * rate.searchSurchargeCredits * DEFAULT_POLICY.creditMultiplier));
  });

  it("honours creditMultiplier", () => {
    const doubled = { ...DEFAULT_POLICY, creditMultiplier: 2 };
    const rate = DEFAULT_POLICY.rates[0];
    const single = creditsForUsage(DEFAULT_POLICY, rate, { inputTokens: 1_000_000, outputTokens: 0, searchCount: 0, audioInput: false });
    const twice = creditsForUsage(doubled, rate, { inputTokens: 1_000_000, outputTokens: 0, searchCount: 0, audioInput: false });
    expect(twice).toBe(single * 2);
  });
});

describe("maxOutputTokensForModel", () => {
  it("returns 65536 for gemini-3.x and gemini-2.5", () => {
    expect(maxOutputTokensForModel("gemini-3-flash-preview")).toBe(65536);
    expect(maxOutputTokensForModel("gemini-3.1-pro-preview")).toBe(65536);
    expect(maxOutputTokensForModel("gemini-2.5-flash")).toBe(65536);
  });

  it("returns 8192 otherwise", () => {
    expect(maxOutputTokensForModel("some-other")).toBe(8192);
    expect(maxOutputTokensForModel(undefined)).toBe(8192);
  });
});
