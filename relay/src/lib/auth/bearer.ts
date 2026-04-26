/**
 * Extract either an admin bearer (matches `RELAY_BEARER_TOKEN` + any rotating
 * tokens with admin scope) or a per-device client key (`rk_...`) from the
 * request. The watch app sends exactly one `Authorization: Bearer ...` header
 * so both cases land here.
 *
 * Admin-issued rotating tokens carry a `scope` (`admin` | `client`) plus
 * optional `allowedEndpoints` and `ipAllowlist` constraints. We honor those
 * here so a "client" scoped token cannot authenticate as admin and operators
 * can scope a token to specific endpoints / source IPs.
 */

import { config } from "@/lib/config";
import { billingStore } from "@/lib/store/billing-store";
import { settingsStore, type AdminToken } from "@/lib/store/settings-store";
import type { Key } from "@/lib/billing/types";

export interface AuthContext {
  kind: "admin" | "client";
  token: string;
  clientKey?: Key;
  tokenLabel?: string;
  tokenID?: string;
  allowedEndpoints?: string[];
  ipAllowlist?: string[];
  rpmLimit?: number;
}

function clientIp(request: Request): string | undefined {
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    request.headers.get("x-real-ip") ||
    undefined
  );
}

function tokenAuthorisedForRequest(token: AdminToken, request: Request): boolean {
  if (token.expiresAt && Date.parse(token.expiresAt) < Date.now()) return false;
  if (token.allowedEndpoints && token.allowedEndpoints.length > 0) {
    const path = new URL(request.url).pathname;
    const matches = token.allowedEndpoints.some((pattern) => {
      if (pattern === path) return true;
      if (pattern.endsWith("/*")) return path.startsWith(pattern.slice(0, -1));
      return false;
    });
    if (!matches) return false;
  }
  if (token.ipAllowlist && token.ipAllowlist.length > 0) {
    const ip = clientIp(request);
    if (!ip || !token.ipAllowlist.includes(ip)) return false;
  }
  return true;
}

export async function authenticate(request: Request): Promise<AuthContext | null> {
  const header = request.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) return null;
  const token = header.slice(7).trim();
  if (!token) return null;

  if (config.relayBearerToken && token === config.relayBearerToken) {
    return { kind: "admin", token, tokenLabel: "env" };
  }

  const match = await settingsStore().findAdminTokenByPlaintext(token);
  if (match) {
    if (!tokenAuthorisedForRequest(match, request)) return null;
    settingsStore().touchToken(match.id).catch(() => undefined);
    if (match.scope === "client") return null;
    return {
      kind: "admin",
      token,
      tokenLabel: match.label,
      tokenID: match.id,
      allowedEndpoints: match.allowedEndpoints,
      ipAllowlist: match.ipAllowlist,
      rpmLimit: match.rpmLimit,
    };
  }

  if (token.startsWith("rk_")) {
    const key = await billingStore().findKeyByValue(token);
    if (key && key.state === "active") return { kind: "client", token, clientKey: key };
  }
  return null;
}
