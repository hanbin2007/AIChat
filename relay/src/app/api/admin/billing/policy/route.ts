import { requireOperator } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { MeteringPolicy, Plan } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const guard = await requireOperator();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as { policy?: MeteringPolicy; plans?: Plan[] } | null;
  if (!body?.policy || !body?.plans) return errorResponse(400, "policy and plans required.");
  const previous = (await billingStore().listAll());
  await billingStore().updatePolicy(body.policy, body.plans);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "billing.policy.update",
    before: { policy: previous.policy, plans: previous.plans },
    after: { policy: body.policy, plans: body.plans },
  });
  return jsonResponse(200, { ok: true });
}
