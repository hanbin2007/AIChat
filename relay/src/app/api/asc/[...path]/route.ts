import { type NextRequest, NextResponse } from "next/server";

// Generic transparent proxy for App Store Connect REST API.
//
// Why this exists: Anthropic's Claude Code Routines sandbox can't reach
// `api.appstoreconnect.apple.com` directly — either Anthropic's egress proxy
// blocks the apple.com domain (despite "Full" network tier) or Apple's edge
// rejects Anthropic's datacenter IP range. From an AWS Singapore host (this
// relay), Apple is reachable, so the routine talks to us instead.
//
// Wire: routine sends `https://<relay>/asc/v1/...` with its own ES256 JWT in
// `Authorization`. We forward to `https://api.appstoreconnect.apple.com/v1/...`
// preserving method, headers (notably Authorization), query string, and body.
// We do NOT add or strip auth — the JWT is end-to-end. Anyone abusing this
// proxy still needs a valid ASC private key to mint a JWT, so the bearer-
// token gate every other relay endpoint has would just complicate the routine
// without adding security.

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ASC_ORIGIN = "https://api.appstoreconnect.apple.com";

// Hop-by-hop headers we must not forward (RFC 7230 §6.1) plus Next/runtime
// noise that breaks fetch when re-sent.
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
  "content-length", // fetch sets this from body
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-real-ip",
]);

const STRIP_RESPONSE_HEADERS = new Set([
  "transfer-encoding",
  "connection",
  "keep-alive",
  "content-encoding", // upstream may gzip; we hand back a fresh body
  "content-length",
]);

async function proxy(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const { path } = await params;
  const upstreamPath = path.join("/");
  const search = req.nextUrl.search; // includes the `?` if any
  const upstreamUrl = `${ASC_ORIGIN}/${upstreamPath}${search}`;

  const headers = new Headers();
  req.headers.forEach((value, key) => {
    if (!STRIP_REQUEST_HEADERS.has(key.toLowerCase())) headers.set(key, value);
  });

  const init: RequestInit = {
    method: req.method,
    headers,
    redirect: "manual",
  };
  if (req.method !== "GET" && req.method !== "HEAD") {
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
export const PATCH = proxy;
export const PUT = proxy;
export const DELETE = proxy;
export const HEAD = proxy;
export const OPTIONS = proxy;
