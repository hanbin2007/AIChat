import { beforeEach, describe, expect, it } from "vitest";
import { POST } from "@/app/api/v1/activation/bootstrap/route";
import { makeRequest, resetState } from "../helpers";

describe("POST /api/v1/activation/bootstrap", () => {
  beforeEach(resetState);

  it("rejects missing deviceID", async () => {
    const res = await POST(
      makeRequest({ url: "http://test/api/v1/activation/bootstrap", method: "POST", body: { platform: "watch" } }),
    );
    expect(res.status).toBe(400);
  });

  it("accepts snake_case device_id", async () => {
    const res = await POST(
      makeRequest({
        url: "http://test/api/v1/activation/bootstrap",
        method: "POST",
        body: { device_id: "d1", platform: "watch" },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { account: { source: string } };
    expect(body.account.source).toBe("trial");
  });

  it("coerces unknown platforms to 'unknown'", async () => {
    const res = await POST(
      makeRequest({
        url: "http://test/api/v1/activation/bootstrap",
        method: "POST",
        body: { deviceID: "d2", platform: "nintendo" },
      }),
    );
    const body = (await res.json()) as { device: { platform: string } };
    expect(body.device.platform).toBe("unknown");
  });

  it("is idempotent: calling twice with the same deviceID yields the same account", async () => {
    const mk = () =>
      POST(
        makeRequest({
          url: "http://test/api/v1/activation/bootstrap",
          method: "POST",
          body: { deviceID: "d3", platform: "watch" },
        }),
      );
    const a = (await (await mk()).json()) as { account: { accountID: string } };
    const b = (await (await mk()).json()) as { account: { accountID: string } };
    expect(a.account.accountID).toBe(b.account.accountID);
  });
});
