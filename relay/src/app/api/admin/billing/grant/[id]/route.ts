import { requireAdmin } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { Grant } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function PATCH(req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  const body = (await req.json().catch(() => null)) as Partial<Grant> | null;
  if (!body) return errorResponse(400, "Invalid body.");
  try {
    const updated = await billingStore().modifyGrant(id, body);
    await auditLog().append({
      actor: guard.session.sub,
      role: guard.session.role,
      action: "grant.modify",
      target: id,
      after: {
        remainingCredits: updated.remainingCredits,
        expiresAt: updated.expiresAt,
        note: updated.note,
      },
    });
    return jsonResponse(200, updated);
  } catch (err) {
    return errorResponse(404, (err as Error).message);
  }
}
