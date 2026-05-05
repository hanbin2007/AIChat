/**
 * Extract either an admin bearer (matches `RELAY_BEARER_TOKEN` + any rotating
 * tokens configured in settings) or a per-device client key (`rk_...`) from
 * the request. The watch app sends exactly one `Authorization: Bearer ...`
 * header so both cases land here.
 */

import { config } from "@/lib/config";
import { billingStore } from "@/lib/store/billing-store";
import { settingsStore } from "@/lib/store/settings-store";
import type { Key } from "@/lib/billing/types";

export interface AuthContext {
  kind: "admin" | "client";
  token: string;
  clientKey?: Key;
  tokenLabel?: string;
}

export async function authenticate(request: Request): Promise<AuthContext | null> {
  const header = request.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice(7).trim();
  if (!token) return null;

  // Master env-configured bearer.
  if (config.relayBearerToken && token === config.relayBearerToken) {
    return { kind: "admin", token, tokenLabel: "env" };
  }

  // Admin-issued rotating tokens.
  const settings = await settingsStore().get();
  const match = settings.adminTokens.find((t) => t.value === token && !t.revoked);
  if (match) {
    settingsStore().touchToken(match.id).catch(() => undefined);
    return { kind: "admin", token, tokenLabel: match.label };
  }

  // Per-device client key. Both the key and its parent account must be
  // active — otherwise an admin-paused or expired account would still
  // pass auth as long as the key record itself wasn't flipped, and end
  // up at reserveCredits where the account-level gates would reject it
  // with a confusing 402 instead of a clean 401.
  if (token.startsWith("rk_")) {
    const key = await billingStore().findKeyByValue(token);
    if (!key || key.state !== "active") return null;
    const account = await billingStore().findAccount(key.accountID);
    if (!account || account.state !== "active") return null;
    return { kind: "client", token, clientKey: key };
  }
  return null;
}
