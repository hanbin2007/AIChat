import { requireAdmin } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function DELETE(_req: Request, context: { params: Promise<{ token: string }> }) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const { token } = await context.params;
  await billingStore().revokePairingToken(token);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "pairing.token.revoke",
    target: token,
  });
  return jsonResponse(200, { ok: true });
}
