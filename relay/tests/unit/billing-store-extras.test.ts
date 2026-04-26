import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { billingStore } from "@/lib/store/billing-store";
import { resetClock, setClock } from "@/lib/clock";
import { resetState } from "../helpers";

describe("BillingStore — new operator actions & time-based compact", () => {
  beforeEach(resetState);
  afterEach(resetClock);

  describe("unbindDevice", () => {
    it("removes device, revokes its key, deactivates orphan account", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "w1", platform: "watch" });
      await billingStore().unbindDevice(boot.device.deviceID);
      const snap = await billingStore().snapshot();
      expect(snap.devices[boot.device.deviceID]).toBeUndefined();
      expect(snap.keys[boot.key.keyID].state).toBe("revoked");
      expect(snap.accounts[boot.account.accountID].state).toBe("inactive");
    });

    it("leaves account active when another device remains", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "main", platform: "iPhone" });
      const token = await billingStore().issuePairingToken({
        accountID: boot.account.accountID,
        deviceID: boot.device.deviceID,
      });
      await billingStore().joinPaired({
        pairingToken: token.token,
        deviceID: "watch-1",
        platform: "watch",
      });
      await billingStore().unbindDevice(boot.device.deviceID);
      const snap = await billingStore().snapshot();
      expect(snap.accounts[boot.account.accountID].state).toBe("active");
    });

    it("throws on unknown deviceID", async () => {
      await expect(billingStore().unbindDevice("not-there")).rejects.toThrow();
    });
  });

  describe("revokePairingToken", () => {
    it("deletes the pending token", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "d1", platform: "watch" });
      const t = await billingStore().issuePairingToken({
        accountID: boot.account.accountID,
        deviceID: boot.device.deviceID,
      });
      await billingStore().revokePairingToken(t.token);
      const snap = await billingStore().snapshot();
      expect(snap.pairingTokens[t.token]).toBeUndefined();
    });
  });

  describe("time-based compact", () => {
    it("zeros expired trial grants after the trial window closes", async () => {
      const baseline = new Date("2026-05-01T00:00:00Z");
      setClock(() => baseline);
      const boot = await billingStore().bootstrapTrial({ deviceID: "d1", platform: "watch" });
      const snap = await billingStore().snapshot();
      expect(snap.accounts[boot.account.accountID].creditBalance).toBe(800);

      // Jump the clock forward past trialDurationDays (default 7).
      setClock(() => new Date("2026-05-15T00:00:00Z"));
      delete (globalThis as { __billingStore?: unknown }).__billingStore;
      // Fresh store — ensureLoaded() runs compact with the new clock.
      const after = await billingStore().snapshot();
      expect(after.accounts[boot.account.accountID].creditBalance).toBe(0);
      expect(after.grants[boot.grant.grantID].remainingCredits).toBe(0);
    });

    it("evicts expired pairing tokens on load", async () => {
      setClock(() => new Date("2026-05-01T00:00:00Z"));
      const boot = await billingStore().bootstrapTrial({ deviceID: "m1", platform: "iPhone" });
      const t = await billingStore().issuePairingToken({
        accountID: boot.account.accountID,
        deviceID: boot.device.deviceID,
      });
      setClock(() => new Date("2026-05-01T00:30:00Z")); // > 10min TTL
      delete (globalThis as { __billingStore?: unknown }).__billingStore;
      const after = await billingStore().snapshot();
      expect(after.pairingTokens[t.token]).toBeUndefined();
    });

    it("marks unused activation codes as expired past their expiresAt", async () => {
      setClock(() => new Date("2026-05-01T00:00:00Z"));
      const [code] = await billingStore().createActivationCodes({
        count: 1,
        credits: 100,
        expiresAt: new Date("2026-05-10T00:00:00Z").toISOString(),
      });
      setClock(() => new Date("2026-05-20T00:00:00Z"));
      delete (globalThis as { __billingStore?: unknown }).__billingStore;
      const after = await billingStore().snapshot();
      expect(after.activationCodes[code.code].state).toBe("expired");
    });
  });

  describe("submitPurchase — device re-attachment", () => {
    it("detaches a device from its old account when the same device resubmits under a new JWS", async () => {
      const { forgeJws } = await import("../helpers");
      const firstJws = forgeJws({
        transactionId: "tx-1",
        originalTransactionId: "tx-1",
        productId: "com.aichat.relay.flash.monthly",
      });
      const first = await billingStore().submitPurchase({
        signedTransactionInfo: firstJws,
        deviceID: "d1",
        platform: "watch",
      });
      // Pretend the same device buys under a different originalTransactionID.
      const secondJws = forgeJws({
        transactionId: "tx-2",
        originalTransactionId: "tx-other",
        productId: "com.aichat.relay.pro.monthly",
      });
      const second = await billingStore().submitPurchase({
        signedTransactionInfo: secondJws,
        deviceID: "d1",
        platform: "watch",
      });
      expect(second.account.accountID).not.toBe(first.account.accountID);
      const snap = await billingStore().snapshot();
      expect(snap.accounts[first.account.accountID].deviceIDs).not.toContain("d1");
      expect(snap.accounts[second.account.accountID].deviceIDs).toContain("d1");
    });
  });
});
