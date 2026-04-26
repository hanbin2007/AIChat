import { readSession, type SessionPayload } from "@/lib/auth/session";
import { errorResponse } from "@/lib/api/error";

export type Role = SessionPayload["role"];

/** Any authenticated admin (operator / support / viewer). */
export async function requireAdmin() {
  const session = await readSession();
  if (!session) return { ok: false as const, response: errorResponse(401, "Admin session required.") };
  return { ok: true as const, session };
}

/** Caller must hold one of the specified roles. */
export async function requireRole(...roles: Role[]) {
  const session = await readSession();
  if (!session) return { ok: false as const, response: errorResponse(401, "Admin session required.") };
  if (!roles.includes(session.role)) {
    return {
      ok: false as const,
      response: errorResponse(403, `Forbidden — requires role: ${roles.join(" / ")}.`),
    };
  }
  return { ok: true as const, session };
}

/** Convenience: operator-only routes (settings, tokens, RBAC, diagnostics). */
export const requireOperator = () => requireRole("operator");

/** Convenience: billing CS routes — operator OR support. */
export const requireBillingWrite = () => requireRole("operator", "support");
