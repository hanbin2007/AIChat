/**
 * StoreKit JWS decoder + verifier.
 *
 * `decodeJwsPayload` extracts transactionID / productID / etc. from the
 * base64url payload (used both standalone and after verification).
 *
 * `verifyJws` performs real StoreKit JWS verification: it ES256-verifies
 * `base64url(header).base64url(payload)` against the public key of the leaf
 * certificate in the `x5c` protected-header chain, validates the x5c chain up
 * to Apple's pinned StoreKit root CA, and requires `alg === "ES256"`. On any
 * failure it THROWS (callers return 400/401).
 *
 * Verification is gated behind `BILLING_JWS_VERIFY`: it runs unless the env
 * var is exactly the string `"false"` (i.e. it defaults ON).
 */

import { createVerify, X509Certificate } from "node:crypto";

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
    const raw = Buffer.from(part, "base64url").toString("utf8");
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

/** Whether cryptographic JWS verification is enabled (default ON). */
export function jwsVerifyEnabled(): boolean {
  return process.env.BILLING_JWS_VERIFY !== "false";
}

interface JwsHeader {
  alg?: string;
  x5c?: string[];
}

/**
 * Apple's StoreKit certificates chain up to the "Apple Root CA - G3" root.
 * The pinned root is supplied via `STOREKIT_ROOT_CA_PEM` (PEM, may contain
 * multiple concatenated certs) or `STOREKIT_ROOT_CA_PEM_PATH`. When neither
 * is set we still verify the leaf signature + intra-chain links, but cannot
 * anchor to Apple's root — that case throws so an operator must configure the
 * pin before enabling verification in production.
 */
function loadPinnedRoots(): X509Certificate[] {
  const inline = process.env.STOREKIT_ROOT_CA_PEM;
  let pem = inline;
  if (!pem) {
    const p = process.env.STOREKIT_ROOT_CA_PEM_PATH;
    if (p) {
      // Lazy require to avoid bundling fs into edge contexts.
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const fs = require("node:fs") as typeof import("node:fs");
      try {
        pem = fs.readFileSync(p, "utf8");
      } catch {
        pem = undefined;
      }
    }
  }
  if (!pem) return [];
  // Split a bundle into individual PEM blocks.
  const blocks = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g) ?? [];
  const roots: X509Certificate[] = [];
  for (const block of blocks) {
    try {
      roots.push(new X509Certificate(block));
    } catch {
      /* skip malformed block */
    }
  }
  return roots;
}

function certFromDerBase64(b64: string): X509Certificate {
  // x5c entries are standard base64 (not base64url) DER.
  return new X509Certificate(Buffer.from(b64, "base64"));
}

function isTimeValid(cert: X509Certificate, at: Date): boolean {
  const notBefore = new Date(cert.validFrom).getTime();
  const notAfter = new Date(cert.validTo).getTime();
  const t = at.getTime();
  return Number.isFinite(notBefore) && Number.isFinite(notAfter) && t >= notBefore && t <= notAfter;
}

/**
 * Verify a StoreKit JWS. Throws on any failure. Returns the decoded payload on
 * success. When verification is disabled via `BILLING_JWS_VERIFY=false` this
 * decodes without cryptographic checks.
 */
export function verifyJws(jws: string, options?: { roots?: X509Certificate[]; at?: Date }): DecodedTransaction {
  if (!jwsVerifyEnabled()) {
    return decodeJwsPayload(jws);
  }

  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("Malformed JWS: expected three segments.");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  const header = base64urlDecodeJson<JwsHeader>(encodedHeader);
  if (!header) throw new Error("Malformed JWS header.");
  if (header.alg !== "ES256") throw new Error(`Unsupported JWS alg: ${header.alg ?? "<none>"}.`);
  if (!Array.isArray(header.x5c) || header.x5c.length === 0) {
    throw new Error("JWS header missing x5c certificate chain.");
  }

  const at = options?.at ?? new Date();

  // Parse the certificate chain (leaf first).
  let chain: X509Certificate[];
  try {
    chain = header.x5c.map(certFromDerBase64);
  } catch {
    throw new Error("JWS x5c chain contains an unparseable certificate.");
  }

  // Validity windows.
  for (const cert of chain) {
    if (!isTimeValid(cert, at)) throw new Error("JWS certificate outside its validity window.");
  }

  // Each cert (except the last) must be signed by the next one in the chain.
  for (let i = 0; i < chain.length - 1; i++) {
    if (!chain[i].verify(chain[i + 1].publicKey)) {
      throw new Error("JWS x5c chain link verification failed.");
    }
  }

  // Anchor the chain to a pinned root CA.
  const roots = options?.roots ?? loadPinnedRoots();
  if (roots.length === 0) {
    throw new Error(
      "No pinned StoreKit root CA configured (set STOREKIT_ROOT_CA_PEM). Refusing to verify against an unanchored chain.",
    );
  }
  const top = chain[chain.length - 1];
  const anchored = roots.some((root) => {
    if (top.fingerprint256 === root.fingerprint256) return true; // root included in x5c
    try {
      return top.verify(root.publicKey);
    } catch {
      return false;
    }
  });
  if (!anchored) throw new Error("JWS x5c chain does not anchor to the pinned StoreKit root CA.");

  // ES256-verify the signing input against the leaf public key.
  const leaf = chain[0];
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = Buffer.from(encodedSignature, "base64url");
  const verifier = createVerify("sha256");
  verifier.update(signingInput);
  verifier.end();
  const ok = verifier.verify({ key: leaf.publicKey, dsaEncoding: "ieee-p1363" }, signature);
  if (!ok) throw new Error("JWS signature verification failed.");

  return decodeJwsPayload(jws);
}
