import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { middleware } from "@/middleware";

function makeNextRequest(
  url: string,
  init?: { method?: string; headers?: Record<string, string> },
): NextRequest {
  return new NextRequest(new URL(url), {
    method: init?.method ?? "GET",
    headers: init?.headers,
  });
}

describe("middleware", () => {
  beforeEach(() => {
    // Best-effort reset: between tests we can't reach into the module's
    // edge-memory bucket map directly, but we use distinct IPs per test so
    // they don't share counters.
  });
  afterEach(() => {});

  it("passes through (returns NextResponse.next) for non-/api/v1 paths", () => {
    const req = makeNextRequest("http://test/api/admin/login", { method: "GET" });
    const res = middleware(req);
    // NextResponse.next() returns a Response with no body and 200/200
    // status; what matters is we did not short-circuit.
    expect(res.status).toBe(200);
    // No CORS header was set
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });

  it("short-circuits OPTIONS preflight with 204 and CORS headers", () => {
    const req = makeNextRequest("http://test/api/v1/chat/stream", {
      method: "OPTIONS",
      headers: { origin: "https://example.com" },
    });
    const res = middleware(req);
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe("https://example.com");
    expect(res.headers.get("access-control-allow-methods")).toContain("POST");
    expect(res.headers.get("access-control-max-age")).toBe("86400");
  });

  it("OPTIONS without an Origin header still echoes a wildcard origin", () => {
    const req = makeNextRequest("http://test/api/v1/chat/stream", { method: "OPTIONS" });
    const res = middleware(req);
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
  });

  it("attaches CORS + x-relay-request-id headers on a normal call", () => {
    const req = makeNextRequest("http://test/api/v1/chat/stream", {
      method: "POST",
      headers: { "x-forwarded-for": "10.0.0.1" },
    });
    const res = middleware(req);
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("x-relay-request-id")).toMatch(/^req_/);
  });

  it("preserves a caller-provided x-relay-request-id", () => {
    const req = makeNextRequest("http://test/api/v1/chat/stream", {
      method: "POST",
      headers: { "x-relay-request-id": "req_abc123", "x-real-ip": "10.0.0.2" },
    });
    const res = middleware(req);
    expect(res.headers.get("x-relay-request-id")).toBe("req_abc123");
  });

  it("falls back to x-real-ip when x-forwarded-for is absent", () => {
    const req = makeNextRequest("http://test/api/v1/chat/stream", {
      method: "POST",
      headers: { "x-real-ip": "10.0.0.3" },
    });
    const res = middleware(req);
    expect(res.status).toBe(200);
  });

  it("falls back to 'unknown' when no IP header is present", () => {
    const req = makeNextRequest("http://test/api/v1/chat/stream", { method: "POST" });
    const res = middleware(req);
    expect(res.status).toBe(200);
  });

  it("rate-limits an IP after exceeding the per-window ceiling (3000/min)", () => {
    const ip = "10.99.99.99";
    let lastStatus = 200;
    for (let i = 0; i < 3000; i++) {
      const req = makeNextRequest("http://test/api/v1/chat/stream", {
        method: "POST",
        headers: { "x-forwarded-for": ip },
      });
      const res = middleware(req);
      lastStatus = res.status;
    }
    // The 3001st request should be 429.
    const overflow = makeNextRequest("http://test/api/v1/chat/stream", {
      method: "POST",
      headers: { "x-forwarded-for": ip },
    });
    const res = middleware(overflow);
    expect(lastStatus).toBe(200);
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).not.toBeNull();
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
  });
});
