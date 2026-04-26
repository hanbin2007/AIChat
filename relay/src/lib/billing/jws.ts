/**
 * StoreKit JWS decoder. Matches the macOS AIChat Relay's behaviour:
 * decode the base64url payload to read transactionID / productID / etc.
 *
 * In production (`NODE_ENV === "production"`) we refuse to load unless
 * `RELAY_BILLING_MODE === "apple"`. The "stub" mode is only safe for local
 * development. Switching to "apple" wires in real Apple JWS verification —
 * the verifier itself is provided externally; this module enforces the env
 * gate and continues to decode the payload.
 */

import { config } from "@/lib/config";

export interface DecodedTransaction {
  transactionID?: string;
  originalTransactionID?: string;
  productID?: string;
  environment?: string;
  purchaseDate?: string;
  expirationDate?: string;
  revocationDate?: string;
  appAccountToken?: string;
}

function assertProductionMode(): void {
  if (config.nodeEnv !== "production") return;
  if (config.billingMode !== "apple") {
    throw new Error(
      "[jws] RELAY_BILLING_MODE must be 'apple' in production — refusing to accept stub StoreKit transactions.",
    );
  }
}
assertProductionMode();

function base64urlDecodeJson<T>(part: string): T | null {
  try {
    const normalized = part.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
    const raw = Buffer.from(padded, "base64").toString("utf8");
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function decodeJwsPayload(jws: string): DecodedTransaction {
  // Re-assert at decode time so a runtime env flip is also caught.
  assertProductionMode();
  const parts = jws.split(".");
  if (parts.length !== 3) return {};
  const payload = base64urlDecodeJson<Record<string, unknown>>(parts[1]) ?? {};
  // Strict pickString: reject numbers, empty strings, the literal "0".
  const pickString = (...keys: string[]): string | undefined => {
    for (const k of keys) {
      const v = payload[k];
      if (typeof v !== "string") continue;
      const trimmed = v.trim();
      if (!trimmed || trimmed === "0") continue;
      return trimmed;
    }
    return undefined;
  };
  const pickFreeString = (...keys: string[]): string | undefined => {
    for (const k of keys) {
      const v = payload[k];
      if (typeof v === "string" && v.length > 0) return v;
    }
    return undefined;
  };
  const pickEpoch = (...keys: string[]): string | undefined => {
    for (const k of keys) {
      const v = payload[k];
      if (typeof v === "number" && Number.isFinite(v) && v > 0) {
        return new Date(v).toISOString();
      }
      if (typeof v === "string") {
        const ms = Number(v);
        if (Number.isFinite(ms) && ms > 0) return new Date(ms).toISOString();
      }
    }
    return undefined;
  };
  return {
    transactionID: pickString("transactionId"),
    originalTransactionID: pickString("originalTransactionId"),
    productID: pickString("productId"),
    environment: pickFreeString("environment"),
    purchaseDate: pickEpoch("purchaseDate"),
    expirationDate: pickEpoch("expiresDate", "expirationDate"),
    revocationDate: pickEpoch("revocationDate"),
    appAccountToken: pickFreeString("appAccountToken"),
  };
}
