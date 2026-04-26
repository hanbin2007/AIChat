/**
 * RBAC enforcement: operator can do everything, support can do billing
 * writes only, viewer is read-only.
 */

import { beforeEach, describe, expect, it } from "vitest";
import { PATCH as patchSettings } from "@/app/api/admin/settings/route";
import { POST as savePolicy } from "@/app/api/admin/billing/policy/route";
import { POST as issueToken } from "@/app/api/admin/tokens/route";
import { POST as grantCredits } from "@/app/api/admin/billing/grant/route";
import { POST as bootstrap } from "@/app/api/v1/activation/bootstrap/route";
import { GET as billingRead } from "@/app/api/admin/billing/route";
import { GET as bundle } from "@/app/api/admin/diagnostics/bundle/route";
import { POST as pin } from "@/app/api/admin/conversations/[id]/pin/route";
import { encodeSession, makeSession } from "@/lib/auth/session";
import { settingsStore } from "@/lib/store/settings-store";
import { cookieJar, makeRequest, resetState } from "../helpers";

async function signIn(role: "operator" | "support" | "viewer") {
  // Seed an admin user so isSetupComplete() is true (some routes guard on
  // it). Then plant a signed cookie directly.
  await settingsStore().seedAdmin(`${role}-user`, "longenoughpassword", role);
  cookieJar().set("relay_session", encodeSession(makeSession(`${role}-user`, role)));
}

describe("RBAC", () => {
  beforeEach(resetState);

  describe("Operator", () => {
    beforeEach(() => signIn("operator"));

    it("can issue tokens", async () => {
      const res = await issueToken(
        makeRequest({
          url: "http://t/tokens",
          method: "POST",
          body: { label: "deploy", scope: "client", rpmLimit: 100 },
        }),
      );
      expect(res.status).toBe(200);
    });

    it("can save policy", async () => {
      const res = await savePolicy(
        makeRequest({
          url: "http://t/policy",
          method: "POST",
          body: {
            policy: { creditBudgetUSDPer1000Credits: 5, trialCredits: 800, trialDurationDays: 7, lowBalanceThresholdCredits: 300, maxBoundDevices: 5, creditMultiplier: 1, rates: [] },
            plans: [],
          },
        }),
      );
      expect(res.status).toBe(200);
    });

    it("can download diagnostics bundle", async () => {
      const res = await bundle();
      expect(res.status).toBe(200);
    });
  });

  describe("Support", () => {
    beforeEach(() => signIn("support"));

    it("CAN do billing writes (grant credits)", async () => {
      const boot = await (
        await bootstrap(
          makeRequest({
            url: "http://t/bootstrap",
            method: "POST",
            body: { deviceID: "d1", platform: "watch" },
          }),
        )
      ).json();
      const res = await grantCredits(
        makeRequest({
          url: "http://t/grant",
          method: "POST",
          body: { accountID: boot.account.accountID, credits: 1000, source: "subscription" },
        }),
      );
      expect(res.status).toBe(200);
    });

    it("CAN read billing", async () => {
      const res = await billingRead();
      expect(res.status).toBe(200);
    });

    it("CANNOT save settings (operator-only)", async () => {
      const res = await patchSettings(
        makeRequest({
          url: "http://t/settings",
          method: "PATCH",
          body: { gateway: { allowLanClients: false, corsOrigins: [], requestBodyLimitMB: 8 } },
        }),
      );
      expect(res.status).toBe(403);
    });

    it("CANNOT save policy (operator-only)", async () => {
      const res = await savePolicy(
        makeRequest({
          url: "http://t/policy",
          method: "POST",
          body: { policy: {}, plans: [] },
        }),
      );
      expect(res.status).toBe(403);
    });

    it("CANNOT pin conversations (operator-only)", async () => {
      const res = await pin(
        makeRequest({ url: "http://t/pin", method: "POST", body: {} }),
        { params: Promise.resolve({ id: "x" }) },
      );
      expect(res.status).toBe(403);
    });

    it("CANNOT download diagnostics bundle (operator-only)", async () => {
      const res = await bundle();
      expect(res.status).toBe(403);
    });
  });

  describe("Viewer", () => {
    beforeEach(() => signIn("viewer"));

    it("CAN read billing snapshot", async () => {
      const res = await billingRead();
      expect(res.status).toBe(200);
    });

    it("CANNOT grant credits (billing-write only)", async () => {
      const res = await grantCredits(
        makeRequest({
          url: "http://t/grant",
          method: "POST",
          body: { accountID: "x", credits: 100, source: "subscription" },
        }),
      );
      expect(res.status).toBe(403);
    });

    it("CANNOT save settings", async () => {
      const res = await patchSettings(
        makeRequest({ url: "http://t/settings", method: "PATCH", body: {} }),
      );
      expect(res.status).toBe(403);
    });
  });

  describe("Anonymous", () => {
    it("Returns 401 (not 403) on every admin endpoint", async () => {
      cookieJar().clear();
      const settings = await patchSettings(
        makeRequest({ url: "http://t/x", method: "PATCH", body: {} }),
      );
      expect(settings.status).toBe(401);
      const bil = await billingRead();
      expect(bil.status).toBe(401);
    });
  });
});
