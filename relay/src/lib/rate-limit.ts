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

/**
 * Best-effort client IP from proxy headers. Falls back to "unknown" when no
 * forwarding header is present (e.g. direct/local requests). Caddy sits in
 * front of the relay and sets `x-forwarded-for`.
 */
export function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    req.headers.get("x-real-ip") ||
    "unknown"
  );
}

/**
 * Throttle abuse-prone unauthenticated endpoints (trial bootstrap, paired
 * join). Keys on both client IP and the body-supplied deviceID so neither
 * rotating the deviceID nor sharing an IP alone bypasses the limit. Returns a
 * 429 Response when over the limit, otherwise null.
 */
export function enforceAbuseLimit(
  req: Request,
  scope: string,
  deviceID: string | undefined,
  rpm: number,
): Response | null {
  const ip = clientIp(req);
  const limiter = rateLimiter();
  const checks = [`${scope}:ip:${ip}`];
  if (deviceID) checks.push(`${scope}:device:${deviceID}`);
  for (const key of checks) {
    const result = limiter.check(key, rpm);
    if (!result.allowed) {
      return new Response(
        JSON.stringify({ error: "Too many requests. Slow down." }),
        {
          status: 429,
          headers: {
            "Content-Type": "application/json",
            "Retry-After": String(result.retryAfterSec),
          },
        },
      );
    }
  }
  return null;
}
