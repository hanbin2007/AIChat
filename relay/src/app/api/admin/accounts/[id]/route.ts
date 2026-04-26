import { requireAdmin } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET(_req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  const snapshot = await billingStore().snapshot();
  const account = snapshot.accounts[id];
  if (!account) return errorResponse(404, "Account not found.");
  const devices = account.deviceIDs.map((d) => snapshot.devices[d]).filter(Boolean);
  const keys = account.keyIDs.map((k) => snapshot.keys[k]).filter(Boolean);
  const grants = account.grantIDs.map((g) => snapshot.grants[g]).filter(Boolean);
  const usage = snapshot.usage.filter((u) => u.accountID === id);
  return jsonResponse(200, { account, devices, keys, grants, usage });
}
