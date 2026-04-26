import { requireAdmin } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const data = await billingStore().listAll();
  return jsonResponse(200, data);
}
