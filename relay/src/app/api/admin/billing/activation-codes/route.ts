import { requireBillingWrite } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const guard = await requireBillingWrite();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as {
    count?: number;
    plan?: string;
    credits?: number;
    expiresAt?: string;
    allowedModels?: string[];
    note?: string;
  } | null;
  if (!body?.count || !body?.credits) return errorResponse(400, "count, credits required.");
  const codes = await billingStore().createActivationCodes({
    count: body.count,
    plan: body.plan,
    credits: body.credits,
    expiresAt: body.expiresAt,
    allowedModels: body.allowedModels,
    note: body.note,
  });
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "activation.codes.create",
    after: { count: codes.length },
  });
  return jsonResponse(200, { codes });
}
