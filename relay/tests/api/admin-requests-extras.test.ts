import { beforeEach, describe, expect, it } from "vitest";
import { GET as requestsGet, DELETE as requestsDelete } from "@/app/api/admin/requests/route";
import { POST as login } from "@/app/api/admin/login/route";
import { requestLog } from "@/lib/store/request-log";
import { makeRequest, resetState } from "../helpers";

async function signIn() {
  await login(
    makeRequest({
      url: "http://test/login",
      method: "POST",
      body: { username: "admin", password: "testpassword" },
    }),
  );
}

async function seedActivity() {
  await requestLog().recordActivity({
    id: "old_one",
    timestamp: new Date(Date.now() - 60_000).toISOString(),
    level: "info",
    category: "request",
    message: "older request",
    path: "/api/v1/chat/stream",
    modelID: "gemini-3-flash-preview",
  });
  await requestLog().recordActivity({
    id: "recent_one",
    timestamp: new Date().toISOString(),
    level: "error",
    category: "failure",
    message: "needle in haystack",
    path: "/api/v1/audio/transcribe",
    accountID: "acc-1",
    deviceID: "dev-1",
    modelID: "gemini-3-pro",
  });
}

describe("/api/admin/requests filter branches + DELETE", () => {
  beforeEach(async () => {
    await resetState();
    // Belt-and-braces: persistence may have flushed leftover entries from a
    // sibling test file before resetState cleared the data dir. Wipe again.
    await requestLog().clearActivity();
    await signIn();
    await seedActivity();
  });

  it("filters by `since` (ms window)", async () => {
    const res = await requestsGet(
      makeRequest({ url: "http://t/requests?since=10000" }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { requests: { id: string }[] };
    // only the recent (within 10s) entry survives
    expect(body.requests.map((r) => r.id)).toEqual(["recent_one"]);
  });

  it("filters by `q` matching message/path/accountID/deviceID/modelID", async () => {
    const res = await requestsGet(
      makeRequest({ url: "http://t/requests?q=needle" }),
    );
    const body = (await res.json()) as { requests: { id: string }[] };
    expect(body.requests).toHaveLength(1);
    expect(body.requests[0].id).toBe("recent_one");

    // by accountID
    const accRes = await requestsGet(
      makeRequest({ url: "http://t/requests?q=acc-1" }),
    );
    expect(((await accRes.json()) as { requests: unknown[] }).requests).toHaveLength(1);

    // by modelID
    const modelRes = await requestsGet(
      makeRequest({ url: "http://t/requests?q=gemini-3-pro" }),
    );
    expect(((await modelRes.json()) as { requests: unknown[] }).requests).toHaveLength(1);
  });

  it("filters by `path` and `category`", async () => {
    const res = await requestsGet(
      makeRequest({ url: "http://t/requests?path=/api/v1/chat/stream&category=request" }),
    );
    const body = (await res.json()) as { requests: { id: string }[] };
    expect(body.requests.map((r) => r.id)).toEqual(["old_one"]);
  });

  it("DELETE clears the activity buffer", async () => {
    const res = await requestsDelete();
    expect(res.status).toBe(200);
    const after = await requestsGet(makeRequest({ url: "http://t/requests" }));
    const body = (await after.json()) as { requests: unknown[] };
    expect(body.requests).toEqual([]);
  });

  it("DELETE returns 401 without a session", async () => {
    await resetState();
    const res = await requestsDelete();
    expect(res.status).toBe(401);
  });
});
