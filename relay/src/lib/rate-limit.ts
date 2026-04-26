/**
 * Sliding-window in-memory rate limiter. Not horizontally scalable — for
 * multi-instance deployments swap in Redis. The limiter keys on whatever
 * caller decides (bearer token, IP, "global").
 *
 * Also tracks an "in-flight" counter so callers can enforce a maximum number
 * of concurrent streams per key. Use `acquireConcurrent` / `releaseConcurrent`
 * around the streaming work; callers MUST always release on completion.
 */

type Bucket = { windowStart: number; count: number };

const WINDOW_MS = 60_000;
const MAX_BUCKETS = 20_000;

class RateLimiter {
  private buckets = new Map<string, Bucket>();
  private inflight = new Map<string, number>();

  check(key: string, rpm: number): { allowed: boolean; retryAfterSec: number } {
    if (rpm <= 0) return { allowed: true, retryAfterSec: 0 };
    const now = Date.now();
    const bucket = this.buckets.get(key);
    if (!bucket || now - bucket.windowStart >= WINDOW_MS) {
      this.evictIfNeeded();
      this.buckets.set(key, { windowStart: now, count: 1 });
      return { allowed: true, retryAfterSec: 0 };
    }
    if (bucket.count < rpm) {
      bucket.count += 1;
      // Touch for LRU semantics (Map preserves insertion order; re-set bumps).
      this.buckets.delete(key);
      this.buckets.set(key, bucket);
      return { allowed: true, retryAfterSec: 0 };
    }
    const retryAfterSec = Math.ceil((bucket.windowStart + WINDOW_MS - now) / 1000);
    return { allowed: false, retryAfterSec };
  }

  /**
   * Try to occupy a slot in the in-flight pool for `key`. Returns false when
   * the existing in-flight count is already at `cap`. `cap <= 0` disables the
   * check.
   */
  acquireConcurrent(key: string, cap: number): boolean {
    if (cap <= 0) return true;
    const current = this.inflight.get(key) ?? 0;
    if (current >= cap) return false;
    this.inflight.set(key, current + 1);
    return true;
  }

  releaseConcurrent(key: string): void {
    const current = this.inflight.get(key) ?? 0;
    if (current <= 1) this.inflight.delete(key);
    else this.inflight.set(key, current - 1);
  }

  private evictIfNeeded(): void {
    while (this.buckets.size >= MAX_BUCKETS) {
      const oldest = this.buckets.keys().next().value;
      if (!oldest) break;
      this.buckets.delete(oldest);
    }
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
 * High-level enforcement called from route handlers. Reads the operator-edited
 * settings from `settingsStore` and applies global RPM + per-token RPM. Any
 * limit set to `0` is treated as "no limit". Returns `{ allowed: false }` on
 * rejection along with the suggested `Retry-After` value.
 */
export async function enforceTokenLimits(
  token: string | undefined,
): Promise<{ allowed: true } | { allowed: false; retryAfterSec: number; reason: string }> {
  // Lazy-import to keep this module Edge-safe (settings reads from disk).
  const { settingsStore } = await import("@/lib/store/settings-store");
  const settings = await settingsStore().get();
  const rl = rateLimiter();
  const global = rl.check("__global__", settings.rateLimits.globalRpm);
  if (!global.allowed) return { allowed: false, retryAfterSec: global.retryAfterSec, reason: "global_rpm" };
  if (token) {
    const perToken = rl.check(`token:${token}`, settings.rateLimits.perTokenRpm);
    if (!perToken.allowed) return { allowed: false, retryAfterSec: perToken.retryAfterSec, reason: "per_token_rpm" };
  }
  return { allowed: true };
}

/**
 * Acquire a concurrent-stream slot. Returns a release function the caller
 * MUST invoke (in finally) to free the slot. Returns null when the cap is
 * exceeded.
 */
export async function acquireStreamSlot(
  token: string | undefined,
): Promise<(() => void) | null> {
  const { settingsStore } = await import("@/lib/store/settings-store");
  const settings = await settingsStore().get();
  const cap = settings.rateLimits.concurrentStreams;
  const key = token ? `stream:${token}` : "stream:__anonymous__";
  const ok = rateLimiter().acquireConcurrent(key, cap);
  if (!ok) return null;
  return () => rateLimiter().releaseConcurrent(key);
}

/**
 * Verify the incoming request's `Content-Length` against the operator-edited
 * `gateway.requestBodyLimitMB` setting (in addition to the static cap the
 * Edge middleware already enforces). Returns null on accept; an error tuple
 * on reject so the caller can `return errorResponse(413, ...)`.
 */
export async function enforceRequestBodyLimit(
  req: Request,
): Promise<{ allowed: true } | { allowed: false; limitBytes: number }> {
  const cl = Number(req.headers.get("content-length") ?? "0");
  if (!Number.isFinite(cl) || cl <= 0) return { allowed: true };
  const { settingsStore } = await import("@/lib/store/settings-store");
  const settings = await settingsStore().get();
  const limitBytes = Math.floor(settings.gateway.requestBodyLimitMB * 1024 * 1024);
  if (limitBytes > 0 && cl > limitBytes) return { allowed: false, limitBytes };
  return { allowed: true };
}
