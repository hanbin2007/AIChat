import { requireAdmin } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { AccessSource } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as {
    accountID?: string;
    credits?: number;
    source?: AccessSource;
    expiresAt?: string;
    note?: string;
  } | null;
  if (!body?.accountID || !body?.credits || !body?.source) {
    return errorResponse(400, "accountID, credits, source required.");
  }
  const grant = await billingStore().grantCredits({
    accountID: body.accountID,
    credits: body.credits,
    source: body.source,
    expiresAt: body.expiresAt,
    note: body.note,
  });
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "billing.grant.manual",
    target: body.accountID,
    after: grant,
  });
  return jsonResponse(200, grant);
}
