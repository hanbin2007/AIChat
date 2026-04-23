import { beforeEach, describe, expect, it } from "vitest";
import { POST as prepare } from "@/app/api/v1/billing/purchase/prepare/route";
import { POST as submit } from "@/app/api/v1/billing/purchase/submit/route";
import { POST as restore } from "@/app/api/v1/billing/restore/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { forgeJws, makeRequest, resetState } from "../helpers";

describe("purchase / restore flow", () => {
  beforeEach(resetState);

  async function bootstrapClient(deviceID: string): Promise<string> {
    const res = await bootstrap(
      makeRequest({
        url: "http://test/api/v1/activation/bootstrap",
        method: "POST",
        body: { deviceID, platform: "iPhone" },
      }),
    );
    const body = (await res.json()) as { key: { keyValue: string } };
    return body.key.keyValue;
  }

  it("prepare requires auth", async () => {
    const res = await prepare(makeRequest({ url: "http://test/prepare", method: "POST", body: {} }));
    expect(res.status).toBe(401);
  });

  it("prepare returns a fresh appAccountToken for the caller", async () => {
    const key = await bootstrapClient("phone-1");
    const res = await prepare(
      makeRequest({
        url: "http://test/prepare",
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: {},
      }),
    );
    const body = (await res.json()) as { appAccountToken: string };
    expect(body.appAccountToken).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("submit decodes JWS and activates a subscription grant", async () => {
    const key = await bootstrapClient("phone-2");
    const jws = forgeJws({
      transactionId: "tx-1",
      originalTransactionId: "tx-1",
      productId: "com.aichat.relay.flash.monthly",
      environment: "Sandbox",
    });
    const res = await submit(
      makeRequest({
        url: "http://test/submit",
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: { transaction: { signedTransactionInfo: jws } },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { account: { source: string; planID: string } };
    expect(body.account.source).toBe("subscription");
    expect(body.account.planID).toBe("flash_monthly");
  });

  it("submit rejects missing transaction payload", async () => {
    const key = await bootstrapClient("phone-3");
    const res = await submit(
      makeRequest({
        url: "http://test/submit",
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: {},
      }),
    );
    expect(res.status).toBe(400);
  });

  it("restore is idempotent and tolerant of partial failures", async () => {
    const key = await bootstrapClient("phone-4");
    const res = await restore(
      makeRequest({
        url: "http://test/restore",
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: {
          transactions: [
            { signedTransactionInfo: forgeJws({ transactionId: "tx-a", originalTransactionId: "tx-a", productId: "com.aichat.relay.flash.monthly" }) },
            { signedTransactionInfo: "garbage" },
          ],
        },
      }),
    );
    expect(res.status).toBe(200);
  });
});
