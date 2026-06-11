import { randomBytes, randomUUID } from "node:crypto";

export function uuid(): string {
  return randomUUID();
}

/** `rk_<32 hex>` — Swift relay's client-key format. */
export function newClientKey(): string {
  return `rk_${randomBytes(16).toString("hex")}`;
}

/** Short opaque activation code: 6 groups of 4 uppercase alphanumerics. */
export function newActivationCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(24);
  const out: string[] = [];
  for (let i = 0; i < 6; i++) {
    let group = "";
    for (let j = 0; j < 4; j++) group += alphabet[bytes[i * 4 + j] % alphabet.length];
    out.push(group);
  }
  return out.join("-");
}

/**
 * Pairing token with 128 bits of entropy (was 40 bits / `randomBytes(5)`,
 * brute-forceable online). Grouped uppercase hex keeps it human-typeable.
 */
export function newPairingToken(): string {
  return randomBytes(16).toString("hex").toUpperCase().match(/.{1,5}/g)!.join("-");
}

export function newRequestId(): string {
  return `req_${randomBytes(8).toString("hex")}`;
}

export function newBearerToken(): string {
  return `rbt_${randomBytes(24).toString("base64url")}`;
}
