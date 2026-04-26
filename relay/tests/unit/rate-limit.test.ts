import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { rateLimiter } from "@/lib/rate-limit";
import { resetState } from "../helpers";

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

  it("acquireConcurrent honours the configured cap", () => {
    const limiter = rateLimiter();
    expect(limiter.acquireConcurrent("k", 2)).toBe(true);
    expect(limiter.acquireConcurrent("k", 2)).toBe(true);
    expect(limiter.acquireConcurrent("k", 2)).toBe(false);
    limiter.releaseConcurrent("k");
    expect(limiter.acquireConcurrent("k", 2)).toBe(true);
  });

  it("acquireConcurrent treats cap <= 0 as unlimited", () => {
    const limiter = rateLimiter();
    for (let i = 0; i < 50; i++) {
      expect(limiter.acquireConcurrent("k", 0)).toBe(true);
    }
  });
});
