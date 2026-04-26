/**
 * Billing domain types — mirror `AIChat Relay/RelayBillingContracts.swift`.
 * Keep field names snake_case-friendly on the wire (see `io.ts` for the
 * dual-key codec that accepts both snake_case and camelCase input).
 */

export type AccountState = "active" | "paused" | "expired" | "inactive";
export type AccessSource = "trial" | "subscription" | "offlineManual";
export type KeyState = "active" | "paused" | "revoked";
export type DevicePlatform = "iPhone" | "watch" | "mac" | "unknown";

export interface Account {
  accountID: string;
  displayName?: string;
  adminNote?: string;
  state: AccountState;
  source: AccessSource;
  planID?: string;
  originalTransactionID?: string;
  appAccountToken?: string;
  creditBalance: number;
  creditExpiresAt?: string;
  lastUsageAt?: string;
  deviceIDs: string[];
  keyIDs: string[];
  grantIDs: string[];
  createdAt: string;
}

export interface Device {
  deviceID: string;
  accountID: string;
  platform: DevicePlatform;
  alias?: string;
  note?: string;
  keyID?: string;
  lastSeenAt?: string;
}

export interface Key {
  keyID: string;
  accountID: string;
  deviceID?: string;
  keyValue: string;
  state: KeyState;
  source: AccessSource;
  note?: string;
  issuedAt: string;
  lastUsedAt?: string;
}

export interface Grant {
  grantID: string;
  accountID: string;
  source: AccessSource;
  totalCredits: number;
  remainingCredits: number;
  grantedAt: string;
  expiresAt?: string;
  sourceTransactionID?: string;
  note?: string;
}

export interface UsageRecord {
  requestID: string;
  accountID?: string;
  deviceID?: string;
  keyID?: string;
  endpoint: string;
  modelID?: string;
  inputTokens: number;
  outputTokens: number;
  searchCount: number;
  reservedCredits: number;
  settledCredits: number;
  createdAt: string;
}

export interface Transaction {
  transactionID: string;
  originalTransactionID: string;
  productID: string;
  environment: string;
  signedTransactionInfo: string;
  signedRenewalInfo?: string;
  purchaseDate?: string;
  expirationDate?: string;
  revokedDate?: string;
  processedAt: string;
}

export interface TrialClaim {
  deviceID: string;
  accountID: string;
  claimedAt: string;
}

export interface PairingToken {
  token: string;
  accountID: string;
  issuedBy: string; // deviceID
  expiresAt: string;
  consumedBy?: string;
}

export interface ActivationCode {
  code: string;
  plan?: string;
  credits: number;
  expiresAt?: string;
  allowedModels?: string[];
  fingerprint?: string;
  note?: string;
  redeemedBy?: { accountID: string; deviceID: string; redeemedAt: string };
  createdAt: string;
  state: "unused" | "redeemed" | "revoked" | "expired";
}

export interface MeteringRate {
  modelID: string;
  inputCreditsPerMillion: number;
  inputCreditsPerMillionOver200k?: number;
  outputCreditsPerMillion: number;
  outputCreditsPerMillionOver200k?: number;
  audioInputCreditsPerMillion?: number;
  searchSurchargeCredits: number;
}

export interface MeteringPolicy {
  creditBudgetUSDPer1000Credits: number;
  trialCredits: number;
  trialDurationDays: number;
  lowBalanceThresholdCredits: number;
  maxBoundDevices: number;
  creditMultiplier: number;
  rates: MeteringRate[];
}

export interface Plan {
  id: string;
  title: string;
  productID: string;
  priceUSD: number;
  monthlyCredits: number;
}

export interface AccountStatusResponse {
  account: Account;
  device?: Device;
  key?: Key;
  grants: Grant[];
  recentUsage: UsageRecord[];
}
