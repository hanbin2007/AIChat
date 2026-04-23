import { describe, expect, it } from "vitest";
import { decodeJwsPayload } from "@/lib/billing/jws";
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
