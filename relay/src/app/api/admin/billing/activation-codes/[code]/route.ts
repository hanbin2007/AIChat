import { requireBillingWrite } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function DELETE(_req: Request, context: { params: Promise<{ code: string }> }) {
  const guard = await requireBillingWrite();
  if (!guard.ok) return guard.response;
  const { code } = await context.params;
  await billingStore().revokeActivationCode(code);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "activation.code.revoke",
    target: code,
  });
  return jsonResponse(200, { ok: true });
}
