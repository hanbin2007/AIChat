import type { MeteringPolicy, Plan } from "./types";

/** Defaults lifted from `AIChat Relay/RelayBillingStore.swift`. */
export const DEFAULT_POLICY: MeteringPolicy = {
  creditBudgetUSDPer1000Credits: 5,
  trialCredits: 800,
  trialDurationDays: 7,
  lowBalanceThresholdCredits: 300,
  maxBoundDevices: 5,
  creditMultiplier: 1,
  rates: [
    {
      modelID: "gemini-3.1-pro-preview",
      inputCreditsPerMillion: 2000,
      inputCreditsPerMillionOver200k: 4000,
      outputCreditsPerMillion: 12000,
      outputCreditsPerMillionOver200k: 18000,
      searchSurchargeCredits: 14,
    },
    {
      modelID: "gemini-3-flash-preview",
      inputCreditsPerMillion: 500,
      outputCreditsPerMillion: 3000,
      audioInputCreditsPerMillion: 1000,
      searchSurchargeCredits: 14,
    },
    {
      modelID: "gemini-2.5-flash",
      inputCreditsPerMillion: 300,
      outputCreditsPerMillion: 2500,
      audioInputCreditsPerMillion: 1000,
      searchSurchargeCredits: 35,
    },
  ],
};

export const DEFAULT_PLANS: Plan[] = [
  {
    id: "flash_monthly",
    title: "Flash Monthly",
    productID: "com.aichat.relay.flash.monthly",
    priceUSD: 4.99,
    monthlyCredits: 20000,
  },
  {
    id: "pro_monthly",
    title: "Pro Monthly",
    productID: "com.aichat.relay.pro.monthly",
    priceUSD: 19.99,
    monthlyCredits: 90000,
  },
];
