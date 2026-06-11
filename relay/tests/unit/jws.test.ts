import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { X509Certificate, createSign } from "node:crypto";
import { decodeJwsPayload, verifyJws } from "@/lib/billing/jws";
import { forgeJws } from "../helpers";

describe("decodeJwsPayload", () => {
  it("extracts transactionID / productID / originalTransactionID", () => {
    const jws = forgeJws({
      transactionId: "tx-1",
      originalTransactionId: "tx-0",
      productId: "com.aichat.relay.flash.monthly",
      environment: "Sandbox",
    });
    expect(decodeJwsPayload(jws)).toMatchObject({
      transactionID: "tx-1",
      originalTransactionID: "tx-0",
      productID: "com.aichat.relay.flash.monthly",
      environment: "Sandbox",
    });
  });

  it("converts epoch-millisecond dates to ISO strings", () => {
    const purchased = 1_700_000_000_000;
    const expired = 1_800_000_000_000;
    const jws = forgeJws({
      transactionId: "x",
      originalTransactionId: "x",
      productId: "p",
      purchaseDate: purchased,
      expiresDate: expired,
    });
    const decoded = decodeJwsPayload(jws);
    expect(decoded.purchaseDate).toBe(new Date(purchased).toISOString());
    expect(decoded.expirationDate).toBe(new Date(expired).toISOString());
  });

  it("returns an empty object on malformed JWS", () => {
    expect(decodeJwsPayload("")).toEqual({});
    expect(decodeJwsPayload("only.one")).toEqual({});
    expect(decodeJwsPayload("a.b.c")).toEqual({});
  });

  it("ignores payloads whose epoch fields aren't numeric", () => {
    const jws = forgeJws({ transactionId: "x", productId: "p", purchaseDate: "not-a-number" });
    expect(decodeJwsPayload(jws).purchaseDate).toBeUndefined();
  });
});

describe("verifyJws", () => {
  const ORIGINAL = process.env.BILLING_JWS_VERIFY;
  let dir: string;
  let rootCertPem: string;
  let rootCert: X509Certificate;
  let leafKeyPem: string;
  let leafCertDerB64: string;

  // Build a self-signed root CA + a leaf cert signed by it, all ES256/P-256.
  beforeEach(() => {
    process.env.BILLING_JWS_VERIFY = "true";
    dir = mkdtempSync(path.join(os.tmpdir(), "jws-test-"));
    const ssl = (args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });

    // Root CA.
    ssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "root.key"]);
    ssl([
      "req", "-x509", "-new", "-nodes", "-key", "root.key", "-sha256", "-days", "3650",
      "-subj", "/CN=Test StoreKit Root", "-out", "root.crt",
    ]);

    // Leaf key + CSR + cert signed by the root.
    ssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key"]);
    ssl(["req", "-new", "-key", "leaf.key", "-subj", "/CN=Test StoreKit Leaf", "-out", "leaf.csr"]);
    ssl([
      "x509", "-req", "-in", "leaf.csr", "-CA", "root.crt", "-CAkey", "root.key",
      "-CAcreateserial", "-days", "365", "-sha256", "-out", "leaf.crt",
    ]);

    rootCertPem = execFileSync("cat", ["root.crt"], { cwd: dir }).toString();
    rootCert = new X509Certificate(rootCertPem);
    leafKeyPem = execFileSync("cat", ["leaf.key"], { cwd: dir }).toString();
    const leafCert = new X509Certificate(execFileSync("cat", ["leaf.crt"], { cwd: dir }).toString());
    // DER as standard base64 (x5c form).
    leafCertDerB64 = leafCert.raw.toString("base64");
  });

  afterEach(() => {
    if (ORIGINAL === undefined) delete process.env.BILLING_JWS_VERIFY;
    else process.env.BILLING_JWS_VERIFY = ORIGINAL;
    rmSync(dir, { recursive: true, force: true });
  });

  function signedJws(payload: Record<string, unknown>): string {
    const header = { alg: "ES256", typ: "JWT", x5c: [leafCertDerB64] };
    const encHeader = Buffer.from(JSON.stringify(header)).toString("base64url");
    const encPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");
    const signer = createSign("sha256");
    signer.update(`${encHeader}.${encPayload}`);
    signer.end();
    const sig = signer.sign({ key: leafKeyPem, dsaEncoding: "ieee-p1363" });
    return `${encHeader}.${encPayload}.${sig.toString("base64url")}`;
  }

  it("accepts a valid self-signed ES256 chain and returns the decoded payload", () => {
    const jws = signedJws({ transactionId: "tx-9", productId: "p", originalTransactionId: "tx-9" });
    const decoded = verifyJws(jws, { roots: [rootCert] });
    expect(decoded.transactionID).toBe("tx-9");
    expect(decoded.productID).toBe("p");
  });

  it("rejects a tampered payload", () => {
    const jws = signedJws({ transactionId: "tx-9", productId: "p" });
    const [h, , s] = jws.split(".");
    const forgedPayload = Buffer.from(JSON.stringify({ transactionId: "tx-EVIL", productId: "p" })).toString("base64url");
    const tampered = `${h}.${forgedPayload}.${s}`;
    expect(() => verifyJws(tampered, { roots: [rootCert] })).toThrow(/signature verification failed/i);
  });

  it("rejects a tampered signature", () => {
    const jws = signedJws({ transactionId: "tx-9", productId: "p" });
    const [h, p] = jws.split(".");
    const badSig = Buffer.from("not-a-real-signature").toString("base64url");
    expect(() => verifyJws(`${h}.${p}.${badSig}`, { roots: [rootCert] })).toThrow();
  });

  it("rejects a non-ES256 alg", () => {
    const header = { alg: "HS256", typ: "JWT", x5c: [leafCertDerB64] };
    const encHeader = Buffer.from(JSON.stringify(header)).toString("base64url");
    const encPayload = Buffer.from(JSON.stringify({ transactionId: "x", productId: "p" })).toString("base64url");
    expect(() => verifyJws(`${encHeader}.${encPayload}.sig`, { roots: [rootCert] })).toThrow(/alg/i);
  });

  it("rejects a missing x5c chain", () => {
    const header = { alg: "ES256", typ: "JWT" };
    const encHeader = Buffer.from(JSON.stringify(header)).toString("base64url");
    const encPayload = Buffer.from(JSON.stringify({ transactionId: "x", productId: "p" })).toString("base64url");
    expect(() => verifyJws(`${encHeader}.${encPayload}.sig`, { roots: [rootCert] })).toThrow(/x5c/i);
  });

  it("rejects a chain that does not anchor to the pinned root", () => {
    const jws = signedJws({ transactionId: "tx-9", productId: "p" });
    // Anchor against an unrelated root → should fail.
    expect(() => verifyJws(jws, { roots: [] })).toThrow(/pinned/i);
  });

  it("falls back to decode-only when verification is disabled", () => {
    process.env.BILLING_JWS_VERIFY = "false";
    const jws = forgeJws({ transactionId: "tx-7", productId: "p" });
    expect(verifyJws(jws).transactionID).toBe("tx-7");
  });
});
