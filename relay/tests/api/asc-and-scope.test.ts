import { beforeEach, describe, expect, it } from "vitest";
import { GET as ascGet, POST as ascPost } from "@/app/api/asc/[...path]/route";
import { POST as chat } from "@/app/api/v1/chat/stream/route";
import { POST as login } from "@/app/api/admin/login/route";
import { POST as issueToken } from "@/app/api/admin/tokens/route";
import { settingsStore } from "@/lib/store/settings-store";
import { makeRequest, resetState } from "../helpers";
import type { NextRequest } from "next/server";

function nextReq(init: { url: string; method?: string; headers?: Record<string, string>; body?: string }): NextRequest {
  return new Request(init.url, {
    method: init.method ?? "GET",
    headers: init.headers,
    body: init.body,
  }) as unknown as NextRequest;
}

describe("/api/asc proxy auth", () => {
  beforeEach(resetState);

  it("rejects requests without an admin bearer", async () => {
    const res = await ascGet(nextReq({ url: "http://t/asc/v1/apps" }), {
      params: Promise.resolve({ path: ["v1", "apps"] }),
    });
    expect(res.status).toBe(401);
  });

  it("rejects path traversal", async () => {
    const res = await ascGet(
      nextReq({
        url: "http://t/asc/v1/..",
        headers: { "x-asc-relay-bearer": "test-bearer-token" },
      }),
      { params: Promise.resolve({ path: ["v1", ".."] }) },
    );
    expect(res.status).toBe(400);
  });

  it("rejects PATCH (method outside allowlist)", async () => {
    const res = await ascPost(
      nextReq({
        url: "http://t/asc/v1/apps",
        method: "PATCH",
        headers: { "x-asc-relay-bearer": "test-bearer-token" },
      }),
      { params: Promise.resolve({ path: ["v1", "apps"] }) },
    );
    expect(res.status).toBe(405);
  });
});

describe("admin token scope enforcement", () => {
  beforeEach(async () => {
    await resetState();
    await login(
      makeRequest({
        url: "http://t/login",
        method: "POST",
        body: { username: "admin", password: "testpassword" },
      }),
    );
  });

  it("a 'client' scoped token does not authenticate as admin", async () => {
    const issued = await issueToken(
      makeRequest({
        url: "http://t/tokens",
        method: "POST",
        body: { label: "client-scope", scope: "client" },
      }),
    );
    const body = (await issued.json()) as { value: string };
    const tokens = (await settingsStore().get()).adminTokens;
    expect(tokens.find((t) => t.scope === "client")).toBeDefined();
    expect(body.value).toMatch(/^rbt_/);

    // Using the client-scoped token to hit a metered endpoint should NOT
    // resolve as admin (and thus be rejected with 401 once the per-device
    // key requirement kicks in).
    const res = await chat(
      makeRequest({
        url: "http://t/chat",
        method: "POST",
        headers: { Authorization: `Bearer ${body.value}` },
        body: { messages: [{ role: "user", text: "hi" }] },
      }),
    );
    expect(res.status).toBe(401);
  });
});
