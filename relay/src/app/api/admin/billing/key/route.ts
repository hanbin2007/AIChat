import { requireBillingWrite } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { Key } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function PATCH(req: Request) {
  const guard = await requireBillingWrite();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as ({ keyID?: string } & Partial<Key>) | null;
  if (!body?.keyID) return errorResponse(400, "keyID required.");
  try {
    const updated = await billingStore().modifyKey(body.keyID, body);
    await auditLog().append({
      actor: guard.session.sub,
      role: guard.session.role,
      action: "key.modify",
      target: body.keyID,
      after: { state: updated.state, note: updated.note },
    });
    return jsonResponse(200, updated);
  } catch (err) {
    return errorResponse(404, (err as Error).message);
  }
}
