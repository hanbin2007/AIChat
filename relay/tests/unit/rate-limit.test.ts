import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { clientIp, enforceAbuseLimit, rateLimiter } from "@/lib/rate-limit";
import { makeRequest, resetState } from "../helpers";

describe("rate limiter", () => {
  beforeEach(async () => {
    await resetState();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-23T00:00:00Z"));
  });
  afterEach(() => vi.useRealTimers());

  it("allows everything when rpm <= 0", () => {
    for (let i = 0; i < 100; i++) {
      expect(rateLimiter().check("k", 0).allowed).toBe(true);
    }
  });

  it("allows up to rpm then rejects with retryAfter", () => {
    const limiter = rateLimiter();
    for (let i = 0; i < 3; i++) expect(limiter.check("k", 3).allowed).toBe(true);
    const denied = limiter.check("k", 3);
    expect(denied.allowed).toBe(false);
    expect(denied.retryAfterSec).toBeGreaterThan(0);
    expect(denied.retryAfterSec).toBeLessThanOrEqual(60);
  });

  it("resets after the 60-second window", () => {
    const limiter = rateLimiter();
    for (let i = 0; i < 2; i++) limiter.check("k", 2);
    expect(limiter.check("k", 2).allowed).toBe(false);
    vi.advanceTimersByTime(60_000);
    expect(limiter.check("k", 2).allowed).toBe(true);
  });

  it("tracks independent buckets per key", () => {
    const limiter = rateLimiter();
    limiter.check("a", 1);
    expect(limiter.check("a", 1).allowed).toBe(false);
    expect(limiter.check("b", 1).allowed).toBe(true);
  });

  describe("clientIp", () => {
    it("reads the first x-forwarded-for hop", () => {
      const req = makeRequest({ url: "http://t", headers: { "x-forwarded-for": "1.2.3.4, 5.6.7.8" } });
      expect(clientIp(req)).toBe("1.2.3.4");
    });
    it("falls back to x-real-ip then 'unknown'", () => {
      expect(clientIp(makeRequest({ url: "http://t", headers: { "x-real-ip": "9.9.9.9" } }))).toBe("9.9.9.9");
      expect(clientIp(makeRequest({ url: "http://t" }))).toBe("unknown");
    });
  });

  describe("enforceAbuseLimit", () => {
    it("returns null under the limit and a 429 over it", () => {
      const mk = () => makeRequest({ url: "http://t", method: "POST", headers: { "x-forwarded-for": "10.0.0.1" } });
      for (let i = 0; i < 2; i++) {
        expect(enforceAbuseLimit(mk(), "bootstrap", "dev", 2)).toBeNull();
      }
      const blocked = enforceAbuseLimit(mk(), "bootstrap", "dev", 2);
      expect(blocked).not.toBeNull();
      expect(blocked!.status).toBe(429);
      expect(blocked!.headers.get("Retry-After")).toBeTruthy();
    });

    it("throttles a rotating deviceID sharing one IP", () => {
      const mkIp = (ip: string, device: string) => {
        const req = makeRequest({ url: "http://t", method: "POST", headers: { "x-forwarded-for": ip } });
        return enforceAbuseLimit(req, "bootstrap", device, 3);
      };
      // Same IP, rotating deviceIDs — the IP bucket still trips.
      expect(mkIp("11.0.0.1", "a")).toBeNull();
      expect(mkIp("11.0.0.1", "b")).toBeNull();
      expect(mkIp("11.0.0.1", "c")).toBeNull();
      expect(mkIp("11.0.0.1", "d")).not.toBeNull();
    });
  });
});
