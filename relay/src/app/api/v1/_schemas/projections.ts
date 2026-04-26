/**
 * Wire shapes for /api/v1 responses. `Key.keyValue` (the per-device `rk_…`
 * bearer) MUST never leave issuance flows where the client is the rightful
 * recipient (bootstrap / pairing / offline exchange). Status / restore /
 * purchase responses go through `projectAccountStatus` so the secret stays
 * server-side.
 */

import type { AccountStatusResponse, Key } from "@/lib/billing/types";

export interface KeySummary {
  keyID: string;
  accountID: string;
  deviceID?: string;
  state: Key["state"];
  source: Key["source"];
  note?: string;
  issuedAt: string;
  lastUsedAt?: string;
}

export function projectKey(key: Key): KeySummary {
  return {
    keyID: key.keyID,
    accountID: key.accountID,
    deviceID: key.deviceID,
    state: key.state,
    source: key.source,
    note: key.note,
    issuedAt: key.issuedAt,
    lastUsedAt: key.lastUsedAt,
  };
}

export interface AccountStatusProjection extends Omit<AccountStatusResponse, "key"> {
  key?: KeySummary;
}

export function projectAccountStatus(status: AccountStatusResponse): AccountStatusProjection {
  return {
    account: status.account,
    device: status.device,
    grants: status.grants,
    recentUsage: status.recentUsage,
    key: status.key ? projectKey(status.key) : undefined,
  };
}
