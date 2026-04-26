/**
 * Sliding-window in-memory rate limiter. Not horizontally scalable — for
 * multi-instance deployments swap in Redis. The limiter keys on whatever
 * caller decides (bearer token, IP, "global").
 */

type Bucket = { windowStart: number; count: number };

const WINDOW_MS = 60_000;

class RateLimiter {
  private buckets = new Map<string, Bucket>();

  check(key: string, rpm: number): { allowed: boolean; retryAfterSec: number } {
    if (rpm <= 0) return { allowed: true, retryAfterSec: 0 };
    const now = Date.now();
    const bucket = this.buckets.get(key);
    if (!bucket || now - bucket.windowStart >= WINDOW_MS) {
      this.buckets.set(key, { windowStart: now, count: 1 });
      return { allowed: true, retryAfterSec: 0 };
    }
    if (bucket.count < rpm) {
      bucket.count += 1;
      return { allowed: true, retryAfterSec: 0 };
    }
    const retryAfterSec = Math.ceil((bucket.windowStart + WINDOW_MS - now) / 1000);
    return { allowed: false, retryAfterSec };
  }
}

declare global {
  // eslint-disable-next-line no-var
  var __rateLimiter: RateLimiter | undefined;
}

export function rateLimiter(): RateLimiter {
  if (!globalThis.__rateLimiter) globalThis.__rateLimiter = new RateLimiter();
  return globalThis.__rateLimiter;
}
