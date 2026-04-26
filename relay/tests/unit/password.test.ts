import { describe, expect, it } from "vitest";
import { hashPassword, verifyPassword } from "@/lib/auth/password";

describe("password hashing", () => {
  it("round-trips a correct password", () => {
    const hash = hashPassword("hunter2");
    expect(verifyPassword("hunter2", hash)).toBe(true);
  });

  it("rejects wrong passwords", () => {
    const hash = hashPassword("hunter2");
    expect(verifyPassword("hunter3", hash)).toBe(false);
    expect(verifyPassword("", hash)).toBe(false);
  });

  it("produces different salts each call", () => {
    expect(hashPassword("same")).not.toBe(hashPassword("same"));
  });

  it("uses PBKDF2 with the documented iteration count", () => {
    const encoded = hashPassword("x");
    const parts = encoded.split("$");
    expect(parts[0]).toBe("pbkdf2");
    expect(Number(parts[1])).toBeGreaterThan(100_000);
  });

  it("returns false for malformed encoded strings", () => {
    expect(verifyPassword("x", "not-pbkdf2")).toBe(false);
    expect(verifyPassword("x", "pbkdf2$abc$def")).toBe(false);
  });
});
