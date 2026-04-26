import { type NextRequest, NextResponse } from "next/server";
import { authenticate } from "@/lib/auth/bearer";

// Authenticated transparent proxy for App Store Connect REST API.
//
// Why this exists: Anthropic's Claude Code Routines sandbox can't reach
// `api.appstoreconnect.apple.com` directly. From an AWS Singapore host (this
// relay), Apple is reachable, so the routine talks to us instead.
//
// Wire: routine sends `https://<relay>/asc/v1/...` with its own ES256 JWT for
// Apple in `Authorization` headers we forward, AND a relay admin bearer in
// `x-asc-relay-bearer`. The Apple JWT is end-to-end; the relay bearer gates
// access so the relay doesn't act as an open proxy that consumes egress for
// any caller who finds the URL.

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ASC_ORIGIN = "https://api.appstoreconnect.apple.com";

const ALLOWED_METHODS = new Set(["GET", "POST", "PUT", "DELETE", "OPTIONS"]);

const STRIP_REQUEST_HEADERS = new Set([
  "host",
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "content-length",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-real-ip",
  "x-asc-relay-bearer",
]);

const STRIP_RESPONSE_HEADERS = new Set([
  "transfer-encoding",
  "connection",
  "keep-alive",
  "content-encoding",
  "content-length",
]);

function rewriteAuthorizationFromRelayBearer(headers: Headers): void {
  const ascAuth = headers.get("x-asc-authorization");
  if (ascAuth) {
    headers.set("authorization", ascAuth);
    headers.delete("x-asc-authorization");
  }
}

function isSafeSegment(segment: string): boolean {
  if (!segment) return false;
  if (segment === "." || segment === "..") return false;
  if (segment.startsWith("/")) return false;
  if (segment.includes("/")) return false;
  return true;
}

async function proxy(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  if (!ALLOWED_METHODS.has(req.method)) {
    return NextResponse.json({ error: "method_not_allowed" }, { status: 405 });
  }

  // Relay bearer auth — admin only.
  const relayBearerHeader = req.headers.get("x-asc-relay-bearer");
  const relayAuthRequest = new Request(req.url, {
    method: "GET",
    headers: { authorization: relayBearerHeader ? `Bearer ${relayBearerHeader}` : "" },
  });
  const relayAuth = await authenticate(relayAuthRequest);
  if (!relayAuth || relayAuth.kind !== "admin") {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { path } = await params;
  if (!Array.isArray(path) || path.length === 0 || !path.every(isSafeSegment)) {
    return NextResponse.json({ error: "invalid_path" }, { status: 400 });
  }
  const upstreamPath = path.join("/");
  const search = req.nextUrl.search;
  const upstreamUrl = `${ASC_ORIGIN}/${upstreamPath}${search}`;

  const headers = new Headers();
  req.headers.forEach((value, key) => {
    if (!STRIP_REQUEST_HEADERS.has(key.toLowerCase())) headers.set(key, value);
  });
  rewriteAuthorizationFromRelayBearer(headers);

  const init: RequestInit = {
    method: req.method,
    headers,
    redirect: "manual",
  };
  if (req.method !== "GET" && req.method !== "OPTIONS") {
    init.body = await req.arrayBuffer();
  }

  let upstream: Response;
  try {
    upstream = await fetch(upstreamUrl, init);
  } catch (e) {
    return NextResponse.json(
      { error: "asc_proxy_upstream_unreachable", detail: e instanceof Error ? e.message : String(e) },
      { status: 502 },
    );
  }

  const respHeaders = new Headers();
  upstream.headers.forEach((value, key) => {
    if (!STRIP_RESPONSE_HEADERS.has(key.toLowerCase())) respHeaders.set(key, value);
  });

  return new NextResponse(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const DELETE = proxy;
export const OPTIONS = proxy;
