/**
 * Coverage for billing-store fixes introduced alongside the relay infra
 * overhaul: unknown-product rejection, account-state guard on reserve,
 * grant-expiry compaction on the hot path, settle-leak when the account
 * vanishes, and the auto-expire transition that runs inside compact().
 */

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { billingStore, BillingError } from "@/lib/store/billing-store";
import { resetClock, setClock } from "@/lib/clock";
import { forgeJws, resetState } from "../helpers";

describe("BillingStore — infra fixes", () => {
  beforeEach(resetState);
  afterEach(resetClock);

  describe("submitPurchase rejects unknown product", () => {
    it("throws BillingError(400, unknown_product) when no plan matches", async () => {
      const jws = forgeJws({
        transactionId: "tx-x",
        originalTransactionId: "tx-x",
        productId: "com.unknown.plan",
      });
      await expect(
        billingStore().submitPurchase({
          signedTransactionInfo: jws,
          deviceID: "d1",
          platform: "watch",
        }),
      ).rejects.toMatchObject({ statusCode: 400, code: "unknown_product" });
    });
  });

  describe("reserveCredits gating", () => {
    it("rejects when the account is paused", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "d1", platform: "watch" });
      await billingStore().modifyAccount(boot.account.accountID, { state: "paused" });
      await expect(
        billingStore().reserveCredits({
          key: boot.key,
          endpoint: "/api/v1/chat/stream",
          modelID: "gemini-3-flash-preview",
          estimatedInputTokens: 100,
          audioInput: false,
        }),
      ).rejects.toMatchObject({ statusCode: 402, code: "account_inactive" });
    });

    it("zeros expired grants on the hot path even between compact() runs", async () => {
      setClock(() => new Date("2026-05-01T00:00:00Z"));
      const boot = await billingStore().bootstrapTrial({ deviceID: "d1", platform: "watch" });
      // Jump past the trial window without recreating the singleton.
      setClock(() => new Date("2026-05-15T00:00:00Z"));
      await expect(
        billingStore().reserveCredits({
          key: boot.key,
          endpoint: "/api/v1/chat/stream",
          modelID: "gemini-3-flash-preview",
          estimatedInputTokens: 100,
          audioInput: false,
        }),
      ).rejects.toMatchObject({ statusCode: 402 });
    });
  });

  describe("expireAccountsIfStale", () => {
    it("flips an active account with all-expired grants to expired on compact()", async () => {
      setClock(() => new Date("2026-05-01T00:00:00Z"));
      const boot = await billingStore().bootstrapTrial({ deviceID: "d1", platform: "watch" });
      // Walk past the trial window — compact will run on the next mutation.
      setClock(() => new Date("2026-06-01T00:00:00Z"));
      // Trigger a write so compact runs.
      await billingStore().issuePairingToken({
        accountID: boot.account.accountID,
        deviceID: boot.device.deviceID,
      });
      const snap = await billingStore().snapshot();
      expect(snap.accounts[boot.account.accountID].state).toBe("expired");
    });
  });

  describe("settleCredits orphan cleanup", () => {
    it("drops a usage record whose account has been removed", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "d1", platform: "watch" });
      const record = await billingStore().reserveCredits({
        key: boot.key,
        endpoint: "/api/v1/chat/stream",
        modelID: "gemini-3-flash-preview",
        estimatedInputTokens: 100,
        audioInput: false,
      });
      // Forcibly evict the account by reaching into the snapshot — this
      // mirrors the operator-removed-account scenario described in #7.
      const snap = await billingStore().snapshot();
      delete snap.accounts[boot.account.accountID];
      const internal = (await import("@/lib/store/billing-store")).billingStore() as unknown as {
        state: typeof snap;
      };
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (internal as any).state = snap;
      await billingStore().settleCredits({
        requestID: record.requestID,
        inputTokens: 0,
        outputTokens: 0,
        searchCount: 0,
        audioInput: false,
        modelID: "gemini-3-flash-preview",
      });
      const after = await billingStore().snapshot();
      expect(after.usage.find((u) => u.requestID === record.requestID)).toBeUndefined();
    });
  });

  describe("BillingError shape", () => {
    it("exposes statusCode + code so route handlers can map cleanly", () => {
      const err = new BillingError(402, "insufficient_credits");
      expect(err.statusCode).toBe(402);
      expect(err.code).toBe("insufficient_credits");
      expect(err.message).toBe("insufficient_credits");
    });
  });
});
