import { beforeEach, describe, expect, it } from "vitest";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { POST as issuePairing } from "@/app/api/v1/account/pairing-token/route";
import { POST as joinPaired } from "@/app/api/v1/account/join-paired/route";
import { POST as offline } from "@/app/api/v1/offline/exchange/route";
import { billingStore } from "@/lib/store/billing-store";
import { makeRequest, resetState } from "../helpers";

describe("pairing flow end-to-end", () => {
  beforeEach(resetState);

  it("issues a token, joins a device, and confirms the account match", async () => {
    const boot = await (
      await bootstrap(
        makeRequest({
          url: "http://test/api/v1/activation/bootstrap",
          method: "POST",
          body: { deviceID: "phone-1", platform: "iPhone" },
        }),
      )
    ).json();

    const pairing = await (
      await issuePairing(
        makeRequest({
          url: "http://test/api/v1/account/pairing-token",
          method: "POST",
          headers: { Authorization: `Bearer ${boot.key.keyValue}` },
        }),
      )
    ).json();
    expect(pairing.pairingToken).toMatch(/^[0-9A-F-]+$/);

    const joined = await (
      await joinPaired(
        makeRequest({
          url: "http://test/api/v1/account/join-paired",
          method: "POST",
          body: { pairingToken: pairing.pairingToken, deviceID: "watch-1", platform: "watch" },
        }),
      )
    ).json();
    expect(joined.account.accountID).toBe(boot.account.accountID);
  });

  it("rejects missing pairingToken", async () => {
    const res = await joinPaired(
      makeRequest({
        url: "http://test/api/v1/account/join-paired",
        method: "POST",
        body: { deviceID: "x" },
      }),
    );
    expect(res.status).toBe(400);
  });
});

describe("POST /api/v1/offline/exchange", () => {
  beforeEach(resetState);

  it("redeems a valid activation code", async () => {
    const [code] = await billingStore().createActivationCodes({ count: 1, credits: 500 });
    const res = await offline(
      makeRequest({
        url: "http://test/api/v1/offline/exchange",
        method: "POST",
        body: { activationCode: code.code, deviceID: "d1", platform: "watch" },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { account: { source: string }; grants: unknown[] };
    expect(body.account.source).toBe("offlineManual");
    expect(body.grants.length).toBeGreaterThan(0);
  });

  it("rejects unknown codes", async () => {
    const res = await offline(
      makeRequest({
        url: "http://test/api/v1/offline/exchange",
        method: "POST",
        body: { activationCode: "UNUSED", deviceID: "d1", platform: "watch" },
      }),
    );
    expect(res.status).toBe(400);
  });

  it("rejects missing fields", async () => {
    const res = await offline(
      makeRequest({
        url: "http://test/api/v1/offline/exchange",
        method: "POST",
        body: { activationCode: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF" },
      }),
    );
    expect(res.status).toBe(400);
  });
});
