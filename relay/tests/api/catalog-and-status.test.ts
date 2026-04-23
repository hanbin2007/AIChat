import { beforeEach, describe, expect, it } from "vitest";
import { GET as catalog } from "@/app/api/v1/billing/catalog/route";
import { GET as status } from "@/app/api/v1/account/status/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { makeRequest, resetState } from "../helpers";

describe("GET /api/v1/billing/catalog", () => {
  beforeEach(resetState);
  it("returns plans + meteringPolicy unauthenticated", async () => {
    const res = await catalog();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { plans: unknown[]; meteringPolicy: { rates: unknown[] } };
    expect(Array.isArray(body.plans)).toBe(true);
    expect(body.meteringPolicy.rates.length).toBeGreaterThan(0);
  });
});

describe("GET /api/v1/account/status", () => {
  beforeEach(resetState);

  it("returns 401 without credentials", async () => {
    const req = makeRequest({ url: "http://test/api/v1/account/status" });
    const res = await status(req);
    expect(res.status).toBe(401);
  });

  it("returns the bound account when called with a client key", async () => {
    const bootstrapReq = makeRequest({
      url: "http://test/api/v1/activation/bootstrap",
      method: "POST",
      body: { deviceID: "d1", platform: "watch" },
    });
    const bootstrapRes = await bootstrap(bootstrapReq);
    const data = (await bootstrapRes.json()) as { key: { keyValue: string }; account: { accountID: string } };
    const statusReq = makeRequest({
      url: "http://test/api/v1/account/status",
      headers: { Authorization: `Bearer ${data.key.keyValue}` },
    });
    const statusRes = await status(statusReq);
    expect(statusRes.status).toBe(200);
    const body = (await statusRes.json()) as { account: { accountID: string }; grants: unknown[] };
    expect(body.account.accountID).toBe(data.account.accountID);
    expect(body.grants.length).toBeGreaterThan(0);
  });

  it("returns the bound account via x-aichat-device-id", async () => {
    await bootstrap(
      makeRequest({
        url: "http://test/api/v1/activation/bootstrap",
        method: "POST",
        body: { deviceID: "d2", platform: "watch" },
      }),
    );
    const res = await status(
      makeRequest({
        url: "http://test/api/v1/account/status",
        headers: { "x-aichat-device-id": "d2" },
      }),
    );
    expect(res.status).toBe(200);
  });
});
