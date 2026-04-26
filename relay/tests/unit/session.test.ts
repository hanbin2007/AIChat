import { describe, expect, it } from "vitest";
import { decodeSession, encodeSession, makeSession } from "@/lib/auth/session";

describe("session encode / decode", () => {
  it("round-trips a fresh session", () => {
    const payload = makeSession("alice", "operator");
    const encoded = encodeSession(payload);
    const decoded = decodeSession(encoded);
    expect(decoded).toEqual(payload);
  });

  it("rejects a tampered payload (signature fails)", () => {
    const encoded = encodeSession(makeSession("alice"));
    const [body, sig] = encoded.split(".");
    const tampered = `${body.slice(0, -2)}X.${sig}`;
    expect(decodeSession(tampered)).toBeNull();
  });

  it("rejects a tampered signature", () => {
    const encoded = encodeSession(makeSession("alice"));
    const [body] = encoded.split(".");
    expect(decodeSession(`${body}.bogus`)).toBeNull();
  });

  it("rejects expired sessions", () => {
    const expired = encodeSession({
      sub: "alice",
      role: "operator",
      iat: Math.floor(Date.now() / 1000) - 10_000,
      exp: Math.floor(Date.now() / 1000) - 10,
    });
    expect(decodeSession(expired)).toBeNull();
  });

  it("returns null on empty / missing input", () => {
    expect(decodeSession(undefined)).toBeNull();
    expect(decodeSession("")).toBeNull();
    expect(decodeSession("nosplit")).toBeNull();
  });

  it("defaults to operator role", () => {
    expect(makeSession("alice").role).toBe("operator");
  });
});
