import { requireAdmin } from "@/lib/auth/admin-guard";
import { billingStore } from "@/lib/store/billing-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { Device } from "@/lib/billing/types";

export const runtime = "nodejs";

export async function PATCH(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as ({ deviceID?: string } & Partial<Device>) | null;
  if (!body?.deviceID) return errorResponse(400, "deviceID required.");
  const updated = await billingStore().modifyDevice(body.deviceID, body);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "device.modify",
    target: body.deviceID,
    after: updated,
  });
  return jsonResponse(200, updated);
}

export async function DELETE(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const url = new URL(req.url);
  const deviceID = url.searchParams.get("id");
  if (!deviceID) return errorResponse(400, "id required.");
  try {
    await billingStore().unbindDevice(deviceID);
    await auditLog().append({
      actor: guard.session.sub,
      role: guard.session.role,
      action: "device.unbind",
      target: deviceID,
    });
    return jsonResponse(200, { ok: true });
  } catch (err) {
    return errorResponse(404, (err as Error).message);
  }
}
