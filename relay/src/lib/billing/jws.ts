/**
 * StoreKit JWS decoder. Matches the macOS AIChat Relay's behaviour:
 * decode the base64url payload to read transactionID / productID / etc., but
 * DO NOT cryptographically verify the signature in the default stub mode.
 * Strict verification is reserved for v1.2.
 */

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
  const parts = jws.split(".");
  if (parts.length !== 3) return {};
  const payload = base64urlDecodeJson<Record<string, unknown>>(parts[1]) ?? {};
  const pick = (...keys: string[]): string | undefined => {
    for (const k of keys) {
      const v = payload[k];
      if (typeof v === "string" || typeof v === "number") return String(v);
    }
    return undefined;
  };
  const pickDate = (...keys: string[]): string | undefined => {
    const value = pick(...keys);
    if (!value) return undefined;
    const ms = Number(value);
    if (!Number.isFinite(ms)) return undefined;
    return new Date(ms).toISOString();
  };
  return {
    transactionID: pick("transactionId"),
    originalTransactionID: pick("originalTransactionId"),
    productID: pick("productId"),
    environment: pick("environment"),
    purchaseDate: pickDate("purchaseDate"),
    expirationDate: pickDate("expiresDate", "expirationDate"),
    revocationDate: pickDate("revocationDate"),
    appAccountToken: pick("appAccountToken"),
  };
}
