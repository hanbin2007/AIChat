import { beforeEach, describe, expect, it } from "vitest";
import { PATCH as patchAccount } from "@/app/api/admin/billing/account/route";
import { PATCH as patchDevice, DELETE as deleteDevice } from "@/app/api/admin/billing/device/route";
import { PATCH as patchKey } from "@/app/api/admin/billing/key/route";
import { PATCH as patchGrant } from "@/app/api/admin/billing/grant/[id]/route";
import { POST as grantCreditsRoute } from "@/app/api/admin/billing/grant/route";
import { POST as issueCodes } from "@/app/api/admin/billing/activation-codes/route";
import { DELETE as revokeCode } from "@/app/api/admin/billing/activation-codes/[code]/route";
import { POST as savePolicy } from "@/app/api/admin/billing/policy/route";
import { DELETE as revokePairing } from "@/app/api/admin/billing/pairing/[token]/route";
import { GET as accountDetail } from "@/app/api/admin/accounts/[id]/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { POST as login } from "@/app/api/admin/login/route";
import { GET as metricsProm } from "@/app/api/admin/metrics/prometheus/route";
import { POST as issueToken, DELETE as revokeToken } from "@/app/api/admin/tokens/route";
import { billingStore } from "@/lib/store/billing-store";
import { makeRequest, resetState } from "../helpers";

async function seed() {
  const res = await bootstrap(
    makeRequest({
      url: "http://test/api/v1/activation/bootstrap",
      method: "POST",
      body: { deviceID: "phone-1", platform: "iPhone" },
    }),
  );
  return res.json() as Promise<{
    account: { accountID: string };
    device: { deviceID: string };
    key: { keyID: string };
    grants: { grantID: string }[];
  }>;
}

async function signIn() {
  await login(
    makeRequest({
      url: "http://test/login",
      method: "POST",
      body: { username: "admin", password: "testpassword" },
    }),
  );
}

describe("admin billing writes", () => {
  beforeEach(async () => {
    await resetState();
    await signIn();
  });

  it("PATCH /api/admin/billing/account updates displayName/state", async () => {
    const { account } = await seed();
    const res = await patchAccount(
      makeRequest({
        url: "http://t/account",
        method: "PATCH",
        body: { accountID: account.accountID, displayName: "Alice", state: "paused" },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { displayName: string; state: string };
    expect(body.displayName).toBe("Alice");
    expect(body.state).toBe("paused");
  });

  it("PATCH /api/admin/billing/device renames alias + note", async () => {
    const { device } = await seed();
    const res = await patchDevice(
      makeRequest({
        url: "http://t/device",
        method: "PATCH",
        body: { deviceID: device.deviceID, alias: "Kitchen iPhone", note: "on the counter" },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { alias: string; note: string };
    expect(body.alias).toBe("Kitchen iPhone");
    expect(body.note).toBe("on the counter");
  });

  it("DELETE /api/admin/billing/device unbinds + revokes key + deactivates orphan account", async () => {
    const { account, device } = await seed();
    const res = await deleteDevice(
      makeRequest({ url: `http://t/device?id=${device.deviceID}`, method: "DELETE" }),
    );
    expect(res.status).toBe(200);
    const snap = await billingStore().snapshot();
    expect(snap.devices[device.deviceID]).toBeUndefined();
    expect(snap.accounts[account.accountID].state).toBe("inactive");
  });

  it("PATCH /api/admin/billing/key flips state + writes note", async () => {
    const { key } = await seed();
    const res = await patchKey(
      makeRequest({
        url: "http://t/key",
        method: "PATCH",
        body: { keyID: key.keyID, state: "revoked", note: "bad actor" },
      }),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { state: string };
    expect(body.state).toBe("revoked");
  });

  it("PATCH /api/admin/billing/grant/:id adjusts balance + expiry", async () => {
    const { account } = await seed();
    const snap = await billingStore().snapshot();
    const grantID = snap.accounts[account.accountID].grantIDs[0];
    const res = await patchGrant(
      makeRequest({
        url: `http://t/grant/${grantID}`,
        method: "PATCH",
        body: { remainingCredits: 42, note: "adjusted" },
      }),
      { params: Promise.resolve({ id: grantID }) },
    );
    expect(res.status).toBe(200);
    const updated = (await res.json()) as { remainingCredits: number };
    expect(updated.remainingCredits).toBe(42);
  });

  it("POST /api/admin/billing/grant issues manual credits", async () => {
    const { account } = await seed();
    const res = await grantCreditsRoute(
      makeRequest({
        url: "http://t/grant",
        method: "POST",
        body: { accountID: account.accountID, credits: 5000, source: "subscription", note: "apology" },
      }),
    );
    expect(res.status).toBe(200);
    const snap = await billingStore().snapshot();
    expect(snap.accounts[account.accountID].creditBalance).toBe(800 + 5000);
  });

  it("POST /api/admin/billing/activation-codes + DELETE revoke", async () => {
    const issued = await issueCodes(
      makeRequest({
        url: "http://t/codes",
        method: "POST",
        body: { count: 3, credits: 200 },
      }),
    );
    const { codes } = (await issued.json()) as { codes: { code: string }[] };
    expect(codes).toHaveLength(3);

    const target = codes[0].code;
    const revoked = await revokeCode(
      makeRequest({ url: `http://t/codes/${target}`, method: "DELETE" }),
      { params: Promise.resolve({ code: target }) },
    );
    expect(revoked.status).toBe(200);
    const snap = await billingStore().snapshot();
    expect(snap.activationCodes[target].state).toBe("revoked");
  });

  it("POST /api/admin/billing/policy updates multiplier and persists", async () => {
    const snap = await billingStore().snapshot();
    const res = await savePolicy(
      makeRequest({
        url: "http://t/policy",
        method: "POST",
        body: { policy: { ...snap.policy, creditMultiplier: 1.5 }, plans: snap.plans },
      }),
    );
    expect(res.status).toBe(200);
    const after = await billingStore().snapshot();
    expect(after.policy.creditMultiplier).toBe(1.5);
  });

  it("DELETE /api/admin/billing/pairing/:token revokes pending pairing", async () => {
    const { account, device } = await seed();
    const token = await billingStore().issuePairingToken({
      accountID: account.accountID,
      deviceID: device.deviceID,
    });
    const res = await revokePairing(
      makeRequest({ url: `http://t/pairing/${token.token}`, method: "DELETE" }),
      { params: Promise.resolve({ token: token.token }) },
    );
    expect(res.status).toBe(200);
    const snap = await billingStore().snapshot();
    expect(snap.pairingTokens[token.token]).toBeUndefined();
  });

  it("GET /api/admin/accounts/:id bundles account + devices + keys + grants + usage", async () => {
    const { account } = await seed();
    const res = await accountDetail(
      makeRequest({ url: `http://t/accounts/${account.accountID}` }),
      { params: Promise.resolve({ id: account.accountID }) },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { devices: unknown[]; keys: unknown[]; grants: unknown[] };
    expect(body.devices.length).toBeGreaterThan(0);
    expect(body.keys.length).toBeGreaterThan(0);
    expect(body.grants.length).toBeGreaterThan(0);
  });

  it("GET /api/admin/accounts/:id 404 for unknown account", async () => {
    const res = await accountDetail(
      makeRequest({ url: "http://t/accounts/nope" }),
      { params: Promise.resolve({ id: "nope" }) },
    );
    expect(res.status).toBe(404);
  });

  it("GET /api/admin/metrics/prometheus returns text exposition", async () => {
    const res = await metricsProm();
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toMatch(/text\/plain/);
    const body = await res.text();
    expect(typeof body).toBe("string");
  });

  it("POST /api/admin/tokens issues a one-time secret + DELETE revokes", async () => {
    const issued = await issueToken(
      makeRequest({
        url: "http://t/tokens",
        method: "POST",
        body: { label: "deploy", scope: "client", rpmLimit: 300 },
      }),
    );
    expect(issued.status).toBe(200);
    const body = (await issued.json()) as { id: string; value: string };
    expect(body.value).toMatch(/^rbt_/);

    const revoked = await revokeToken(
      makeRequest({ url: `http://t/tokens?id=${body.id}`, method: "DELETE" }),
    );
    expect(revoked.status).toBe(200);
  });

  it("writes audit entries for every admin mutation", async () => {
    const { account } = await seed();
    await patchAccount(
      makeRequest({
        url: "http://t/account",
        method: "PATCH",
        body: { accountID: account.accountID, displayName: "Bob" },
      }),
    );
    const { auditLog } = await import("@/lib/store/audit-log");
    const entries = await auditLog().list();
    expect(entries.some((e) => e.action === "account.modify")).toBe(true);
  });
});
