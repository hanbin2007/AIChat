import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { resetClock, setClock } from "@/lib/clock";
import { resetState } from "../helpers";

/**
 * Regression coverage for the relay billing gates added on top of the existing
 * `kind: client` path:
 *
 * - `authenticate` rejects `rk_...` keys whose parent account is no longer
 *   `active` (paused / expired / inactive). Previously only the key's own
 *   `state` was checked, so an admin pausing the account at the account level
 *   left the key still valid.
 *
 * - `reserveCredits` refuses to bill a non-active account or one whose
 *   `creditExpiresAt` has lapsed. Previously only `creditBalance < reserved`
 *   was guarded, so the first request after the deadline (before the next
 *   `compact()` zeroed expired grants) could still slip through.
 *
 * Admin-token auth is intentionally untouched — the offline-activation flow
 * relies on it for relaying without server-side credit accounting.
 */
describe("relay billing gates", () => {
  beforeEach(resetState);
  afterEach(resetClock);

  // ---- authenticate (rk_ path) -----------------------------------------------

  describe("authenticate", () => {
    it("accepts an rk_ key whose key + account are both active", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "auth-d1", platform: "watch" });
      const req = new Request("http://test/x", {
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
      });
      const auth = await authenticate(req);
      expect(auth?.kind).toBe("client");
      expect(auth?.clientKey?.keyValue).toBe(boot.key.keyValue);
    });

    it("rejects an rk_ key when the parent account is paused", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "auth-d2", platform: "watch" });
      await billingStore().modifyAccount(boot.account.accountID, { state: "paused" });
      const req = new Request("http://test/x", {
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
      });
      expect(await authenticate(req)).toBeNull();
    });

    it("rejects an rk_ key when the parent account is expired", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "auth-d3", platform: "watch" });
      await billingStore().modifyAccount(boot.account.accountID, { state: "expired" });
      const req = new Request("http://test/x", {
        headers: { Authorization: `Bearer ${boot.key.keyValue}` },
      });
      expect(await authenticate(req)).toBeNull();
    });

    it("still accepts the env admin bearer (offline-activation auth path)", async () => {
      const req = new Request("http://test/x", {
        headers: { Authorization: "Bearer test-bearer-token" },
      });
      const auth = await authenticate(req);
      expect(auth?.kind).toBe("admin");
    });
  });

  // ---- reserveCredits --------------------------------------------------------

  describe("reserveCredits", () => {
    it("throws 402 when the account is no longer active", async () => {
      const boot = await billingStore().bootstrapTrial({ deviceID: "rsv-d1", platform: "watch" });
      await billingStore().modifyAccount(boot.account.accountID, { state: "paused" });

      await expect(
        billingStore().reserveCredits({
          key: boot.key,
          endpoint: "/api/v1/chat/stream",
          modelID: "gemini-3-flash-preview",
          estimatedInputTokens: 1_000,
          audioInput: false,
        }),
      ).rejects.toMatchObject({ statusCode: 402 });
    });

    it("throws 402 when account.creditExpiresAt has passed even with balance > 0", async () => {
      // Bootstrap creates a trial grant with expiresAt ~30 days ahead, then we
      // fast-forward the clock past it. compact() is called once on ensureLoaded
      // (at "now") and zeros remainingCredits — but that runs at clock-1, so the
      // bootstrap is fine. We then bump the clock past expiry but BEFORE another
      // write, so creditExpiresAt is still on the cached account record. That's
      // exactly the window the new gate needs to cover.
      const t0 = new Date("2026-01-01T00:00:00Z");
      setClock(() => t0);
      const boot = await billingStore().bootstrapTrial({ deviceID: "rsv-d2", platform: "watch" });
      expect(boot.account.creditBalance).toBeGreaterThan(0);
      expect(boot.account.creditExpiresAt).toBeDefined();

      // Jump to one minute past the trial's expiresAt.
      const t1 = new Date(new Date(boot.account.creditExpiresAt!).getTime() + 60_000);
      setClock(() => t1);

      await expect(
        billingStore().reserveCredits({
          key: boot.key,
          endpoint: "/api/v1/chat/stream",
          modelID: "gemini-3-flash-preview",
          estimatedInputTokens: 1_000,
          audioInput: false,
        }),
      ).rejects.toMatchObject({ statusCode: 402 });
    });

    it("succeeds while creditExpiresAt is still in the future", async () => {
      const t0 = new Date("2026-01-01T00:00:00Z");
      setClock(() => t0);
      const boot = await billingStore().bootstrapTrial({ deviceID: "rsv-d3", platform: "watch" });

      const record = await billingStore().reserveCredits({
        key: boot.key,
        endpoint: "/api/v1/chat/stream",
        modelID: "gemini-3-flash-preview",
        estimatedInputTokens: 1_000,
        audioInput: false,
      });
      expect(record.reservedCredits).toBeGreaterThan(0);
    });
  });
});
