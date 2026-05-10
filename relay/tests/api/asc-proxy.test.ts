import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import {
  GET as ascGet,
  POST as ascPost,
  DELETE as ascDelete,
  PATCH as ascPatch,
  PUT as ascPut,
  HEAD as ascHead,
  OPTIONS as ascOptions,
} from "@/app/api/asc/[...path]/route";
import { resetState } from "../helpers";

function makeReq(
  method: string,
  url: string,
  init?: { headers?: Record<string, string>; body?: BodyInit | null },
): NextRequest {
  return new NextRequest(new URL(url), {
    method,
    headers: init?.headers,
    body: init?.body ?? undefined,
  });
}

describe("asc proxy", () => {
  beforeEach(resetState);
  afterEach(() => vi.unstubAllGlobals());

  it("forwards a GET to api.appstoreconnect.apple.com preserving the path + query string", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ data: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json", "x-apple-rid": "abc" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const req = makeReq(
      "GET",
      "http://relay/api/asc/v1/apps?filter[bundleId]=com.foo&fields=name",
      { headers: { Authorization: "Bearer asc-jwt-token" } },
    );
    const res = await ascGet(req, { params: Promise.resolve({ path: ["v1", "apps"] }) });
    expect(res.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [calledUrl, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(calledUrl).toBe(
      "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=com.foo&fields=name",
    );
    expect((init.headers as Headers).get("authorization")).toBe("Bearer asc-jwt-token");
    // Hop-by-hop / forwarding noise stripped:
    expect((init.headers as Headers).get("host")).toBeNull();
    // GET must not carry a body.
    expect(init.body).toBeUndefined();
    expect(res.headers.get("x-apple-rid")).toBe("abc");
  });

  it("strips response hop-by-hop headers (transfer-encoding, content-encoding, content-length)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response("ok", {
          status: 200,
          headers: {
            "transfer-encoding": "chunked",
            "content-encoding": "gzip",
            "content-length": "2",
            "x-apple-keep": "yes",
          },
        }),
      ),
    );
    const req = makeReq("GET", "http://relay/api/asc/v1/apps");
    const res = await ascGet(req, { params: Promise.resolve({ path: ["v1", "apps"] }) });
    expect(res.headers.get("transfer-encoding")).toBeNull();
    expect(res.headers.get("content-encoding")).toBeNull();
    expect(res.headers.get("content-length")).toBeNull();
    expect(res.headers.get("x-apple-keep")).toBe("yes");
  });

  it("forwards a POST body byte-for-byte", async () => {
    const fetchMock = vi.fn(async () =>
      new Response("{}", { status: 201, headers: { "Content-Type": "application/json" } }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const payload = JSON.stringify({ data: { type: "apps", attributes: { name: "Foo" } } });
    const req = makeReq("POST", "http://relay/api/asc/v1/apps", {
      headers: { Authorization: "Bearer t", "Content-Type": "application/json" },
      body: payload,
    });
    const res = await ascPost(req, { params: Promise.resolve({ path: ["v1", "apps"] }) });
    expect(res.status).toBe(201);
    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    const bodyBuf = init.body as ArrayBuffer;
    expect(Buffer.from(bodyBuf).toString("utf8")).toBe(payload);
  });

  it("returns a 502 envelope when fetch throws", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("getaddrinfo ENOTFOUND");
      }),
    );
    const req = makeReq("GET", "http://relay/api/asc/v1/apps");
    const res = await ascGet(req, { params: Promise.resolve({ path: ["v1", "apps"] }) });
    expect(res.status).toBe(502);
    const body = (await res.json()) as { error: string; detail: string };
    expect(body.error).toBe("asc_proxy_upstream_unreachable");
    expect(body.detail).toContain("ENOTFOUND");
  });

  it("returns 502 with stringified detail when fetch throws a non-Error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw "stringy failure";
      }),
    );
    const req = makeReq("GET", "http://relay/api/asc/v1/apps");
    const res = await ascGet(req, { params: Promise.resolve({ path: ["v1", "apps"] }) });
    expect(res.status).toBe(502);
    const body = (await res.json()) as { detail: string };
    expect(body.detail).toBe("stringy failure");
  });

  it("supports PATCH, PUT, DELETE, HEAD, OPTIONS verbs", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(null, { status: 204 }),
    );
    vi.stubGlobal("fetch", fetchMock);

    for (const [verb, handler] of [
      ["PATCH", ascPatch],
      ["PUT", ascPut],
      ["DELETE", ascDelete],
      ["HEAD", ascHead],
      ["OPTIONS", ascOptions],
    ] as const) {
      const req = makeReq(verb, "http://relay/api/asc/v1/apps/123", {
        headers: { Authorization: "Bearer t" },
        body: verb === "HEAD" || verb === "OPTIONS" ? undefined : "{}",
      });
      const res = await handler(req, { params: Promise.resolve({ path: ["v1", "apps", "123"] }) });
      expect(res.status).toBe(204);
    }
    expect(fetchMock).toHaveBeenCalledTimes(5);
  });
});
