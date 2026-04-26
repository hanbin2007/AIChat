import { requireBillingWrite } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { Account } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function PATCH(req: Request) {
  const guard = await requireBillingWrite();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as ({ accountID?: string } & Partial<Account>) | null;
  if (!body?.accountID) return errorResponse(400, "accountID required.");
  const updated = await billingStore().modifyAccount(body.accountID, body);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "account.modify",
    target: body.accountID,
    after: updated,
  });
  return jsonResponse(200, updated);
}
