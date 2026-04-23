import { beforeEach, describe, expect, it } from "vitest";
import { POST as login } from "@/app/api/admin/login/route";
import { POST as logout } from "@/app/api/admin/logout/route";
import { GET as session, POST as setup } from "@/app/api/admin/setup/route";
import { GET as settingsGet, PATCH as settingsPatch } from "@/app/api/admin/settings/route";
import { GET as audit } from "@/app/api/admin/audit/route";
import { GET as requestsGet } from "@/app/api/admin/requests/route";
import { GET as metrics } from "@/app/api/admin/metrics/route";
import { cookieJar, makeRequest, resetState } from "../helpers";

async function loginAs(username = "admin", password = "testpassword") {
  return login(
    makeRequest({
      url: "http://test/api/admin/login",
      method: "POST",
      body: { username, password },
    }),
  );
}

describe("admin auth flow", () => {
  beforeEach(resetState);

  it("setup returns setupComplete=false until the first admin is created", async () => {
    const pre = await session();
    const preBody = (await pre.json()) as { setupComplete: boolean };
    expect(preBody.setupComplete).toBe(false);

    const res = await setup(
      makeRequest({
        url: "http://test/api/admin/setup",
        method: "POST",
        body: { username: "alice", password: "longenoughpassword" },
      }),
    );
    expect(res.status).toBe(200);

    const post = await session();
    const postBody = (await post.json()) as { setupComplete: boolean };
    expect(postBody.setupComplete).toBe(true);
  });

  it("setup rejects weak passwords", async () => {
    const res = await setup(
      makeRequest({
        url: "http://test/api/admin/setup",
        method: "POST",
        body: { username: "u", password: "short" },
      }),
    );
    expect(res.status).toBe(400);
  });

  it("env-based admin login seeds the admin user and sets a cookie", async () => {
    const res = await loginAs();
    expect(res.status).toBe(200);
    expect(cookieJar().has("relay_session")).toBe(true);
  });

  it("bad password returns 401", async () => {
    const res = await loginAs("admin", "wrong");
    expect(res.status).toBe(401);
  });

  it("logout clears the session cookie", async () => {
    await loginAs();
    expect(cookieJar().has("relay_session")).toBe(true);
    const res = await logout();
    expect(res.status).toBe(200);
    expect(cookieJar().has("relay_session")).toBe(false);
  });
});

describe("admin endpoints reject unauthenticated callers", () => {
  beforeEach(resetState);

  it("401 without session", async () => {
    for (const handler of [settingsGet, audit, requestsGet, metrics]) {
      const res = await handler(makeRequest({ url: "http://test/x" }));
      expect(res.status).toBe(401);
    }
  });
});

describe("admin settings + requests after login", () => {
  beforeEach(async () => {
    await resetState();
    await loginAs();
  });

  it("GET /api/admin/settings returns redacted snapshot", async () => {
    const res = await settingsGet();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { adminTokens: unknown[]; adminUsers: { passwordHash: string }[] };
    expect(Array.isArray(body.adminTokens)).toBe(true);
    if (body.adminUsers.length) expect(body.adminUsers[0].passwordHash).toBe("[redacted]");
  });

  it("PATCH /api/admin/settings writes an audit entry", async () => {
    await settingsPatch(
      makeRequest({
        url: "http://test/settings",
        method: "PATCH",
        body: { gateway: { allowLanClients: false, corsOrigins: [], requestBodyLimitMB: 8 } },
      }),
    );
    const res = await audit(makeRequest({ url: "http://test/audit" }));
    const body = (await res.json()) as { entries: { action: string }[] };
    expect(body.entries.some((e) => e.action === "settings.update")).toBe(true);
  });

  it("GET /api/admin/metrics returns KPIs", async () => {
    const res = await metrics();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { accounts: number; activeKeys: number };
    expect(typeof body.accounts).toBe("number");
    expect(typeof body.activeKeys).toBe("number");
  });

  it("GET /api/admin/requests supports query filters", async () => {
    const res = await requestsGet(
      makeRequest({ url: "http://test/api/admin/requests?level=error" }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { requests: unknown[] };
    expect(Array.isArray(body.requests)).toBe(true);
  });
});
