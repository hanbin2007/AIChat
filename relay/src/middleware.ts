import { NextRequest, NextResponse } from "next/server";

/**
 * Edge middleware. We keep this deliberately lightweight — the full rate
 * limiter / auth stack runs inside the route handlers where the Node runtime
 * is available (settings are read from disk there). Here we:
 *   · set CORS headers for the public /api/v1/* surface
 *   · short-circuit OPTIONS preflights
 *   · attach an X-Relay-Request-Id for log correlation
 *   · apply a coarse per-IP ceiling (LRU windowed counter in edge memory) so a
 *     single IP can't trivially DoS the upstream before the rich rate
 *     limiter inside the handlers fires
 *   · enforce a Content-Length cap so a hostile caller can't stream a huge
 *     body through `req.json()` and into request-log.json
 */

const EDGE_WINDOW_MS = 60_000;
const EDGE_MAX_PER_IP = 3000;
const EDGE_BUCKET_CAP = 20_000;

// `requestBodyLimitMB` setting is also exposed in the settings UI (default 16);
// the env override here keeps Edge middleware free of disk reads.
const DEFAULT_BODY_LIMIT_MB = 16;
function bodyLimitBytes(): number {
  const raw = Number(process.env.RELAY_REQUEST_BODY_LIMIT_MB ?? DEFAULT_BODY_LIMIT_MB);
  const mb = Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_BODY_LIMIT_MB;
  return Math.floor(mb * 1024 * 1024);
}

type Bucket = { windowStart: number; count: number };
const buckets = new Map<string, Bucket>();

function evictIfNeeded(): void {
  while (buckets.size >= EDGE_BUCKET_CAP) {
    const oldest = buckets.keys().next().value;
    if (!oldest) break;
    buckets.delete(oldest);
  }
}

function edgeRateLimit(ip: string): { allowed: boolean; retryAfterSec: number } {
  const now = Date.now();
  const entry = buckets.get(ip);
  if (!entry || now - entry.windowStart >= EDGE_WINDOW_MS) {
    evictIfNeeded();
    buckets.set(ip, { windowStart: now, count: 1 });
    return { allowed: true, retryAfterSec: 0 };
  }
  if (entry.count < EDGE_MAX_PER_IP) {
    entry.count += 1;
    // LRU touch: re-insert to bump position.
    buckets.delete(ip);
    buckets.set(ip, entry);
    return { allowed: true, retryAfterSec: 0 };
  }
  return {
    allowed: false,
    retryAfterSec: Math.ceil((entry.windowStart + EDGE_WINDOW_MS - now) / 1000),
  };
}

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin ?? "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": [
      "Authorization",
      "Content-Type",
      "Idempotency-Key",
      "X-Aichat-Device-Id",
      "X-Aichat-Conversation-Id",
      "X-Aichat-App-Version",
      "X-Aichat-App-Build",
      "X-Aichat-OS",
      "X-Aichat-Device-Model",
      "X-Aichat-Locale",
    ].join(", "),
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function newId(): string {
  return `req_${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36)}`;
}

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Only touch the public API surface.
  if (!pathname.startsWith("/api/v1/")) return NextResponse.next();

  const origin = req.headers.get("origin");
  const cors = corsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new NextResponse(null, { status: 204, headers: cors });
  }

  // Reject oversized bodies before they reach Node-runtime route handlers.
  const contentLength = Number(req.headers.get("content-length") ?? "0");
  const limit = bodyLimitBytes();
  if (Number.isFinite(contentLength) && contentLength > limit) {
    return new NextResponse(
      JSON.stringify({ message: "Request body too large.", limitBytes: limit }),
      {
        status: 413,
        headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
      },
    );
  }

  const ip =
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("x-real-ip") ??
    "unknown";
  const ipLimit = edgeRateLimit(ip);
  if (!ipLimit.allowed) {
    return new NextResponse(
      JSON.stringify({ message: "Too many requests — slow down." }),
      {
        status: 429,
        headers: {
          ...cors,
          "Retry-After": String(ipLimit.retryAfterSec),
          "Content-Type": "application/json; charset=utf-8",
        },
      },
    );
  }

  const requestId = req.headers.get("x-relay-request-id") ?? newId();
  const response = NextResponse.next({
    request: {
      headers: (() => {
        const h = new Headers(req.headers);
        h.set("x-relay-request-id", requestId);
        return h;
      })(),
    },
  });
  for (const [k, v] of Object.entries(cors)) response.headers.set(k, v);
  response.headers.set("x-relay-request-id", requestId);
  return response;
}

export const config = {
  matcher: ["/api/v1/:path*"],
};
