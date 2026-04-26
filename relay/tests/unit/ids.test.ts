import { describe, expect, it } from "vitest";
import {
  newActivationCode,
  newBearerToken,
  newClientKey,
  newPairingToken,
  newRequestId,
  uuid,
} from "@/lib/ids";

describe("id generators", () => {
  it("uuid returns RFC 4122 v4 UUIDs", () => {
    const id = uuid();
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it("newClientKey has the rk_ prefix + 32 hex chars", () => {
    const key = newClientKey();
    expect(key).toMatch(/^rk_[0-9a-f]{32}$/);
  });

  it("newActivationCode is 6 groups of 4 uppercase alphanumerics", () => {
    const code = newActivationCode();
    expect(code).toMatch(/^[A-Z2-9]{4}(-[A-Z2-9]{4}){5}$/);
  });

  it("newPairingToken groups hex characters with dashes", () => {
    expect(newPairingToken()).toMatch(/^[0-9A-F]+(-[0-9A-F]+)+$/);
  });

  it("newPairingToken carries >=128 bits of entropy", () => {
    const t = newPairingToken();
    const hex = t.replace(/-/g, "");
    // 16 random bytes → 32 hex chars.
    expect(hex.length).toBeGreaterThanOrEqual(32);
    // Sanity: 1k draws are unique.
    const seen = new Set<string>();
    for (let i = 0; i < 1000; i++) seen.add(newPairingToken());
    expect(seen.size).toBe(1000);
  });

  it("newRequestId has the req_ prefix", () => {
    expect(newRequestId()).toMatch(/^req_[0-9a-f]{16}$/);
  });

  it("newBearerToken has the rbt_ prefix and sufficient entropy", () => {
    const t = newBearerToken();
    expect(t).toMatch(/^rbt_[A-Za-z0-9_-]+$/);
    expect(t.length).toBeGreaterThan(20);
    expect(new Set([newBearerToken(), newBearerToken(), newBearerToken()]).size).toBe(3);
  });

  it("generates unique values across 1000 draws", () => {
    const seen = new Set();
    for (let i = 0; i < 1000; i++) seen.add(newClientKey());
    expect(seen.size).toBe(1000);
  });
});
