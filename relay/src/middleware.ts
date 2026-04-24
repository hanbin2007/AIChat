import { NextRequest, NextResponse } from "next/server";

/**
 * Edge middleware. We keep this deliberately lightweight — the full rate
 * limiter / auth stack runs inside the route handlers where the Node runtime
 * is available. Here we only:
 *   · set CORS headers for the public /api/v1/* surface
 *   · short-circuit OPTIONS preflights
 *   · attach an X-Relay-Request-Id for log correlation
 *   · apply a coarse per-IP ceiling (windowed counter in edge-memory) so a
 *     single IP can't trivially DoS the upstream before the rich rate
 *     limiter inside the handlers fires.
 */

const EDGE_WINDOW_MS = 60_000;
const EDGE_MAX_PER_IP = 3000;

type Bucket = { windowStart: number; count: number };
const buckets = new Map<string, Bucket>();

function edgeRateLimit(ip: string): { allowed: boolean; retryAfterSec: number } {
  const now = Date.now();
  const entry = buckets.get(ip);
  if (!entry || now - entry.windowStart >= EDGE_WINDOW_MS) {
    buckets.set(ip, { windowStart: now, count: 1 });
    return { allowed: true, retryAfterSec: 0 };
  }
  if (entry.count < EDGE_MAX_PER_IP) {
    entry.count += 1;
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
    "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Aichat-Device-Id, X-Aichat-Conversation-Id",
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

  const ip =
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("x-real-ip") ??
    "unknown";
  const limit = edgeRateLimit(ip);
  if (!limit.allowed) {
    return new NextResponse(
      JSON.stringify({ message: "Too many requests — slow down." }),
      {
        status: 429,
        headers: {
          ...cors,
          "Retry-After": String(limit.retryAfterSec),
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
