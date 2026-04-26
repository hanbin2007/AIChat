import { requireAdmin } from "@/lib/auth/admin-guard";
import { settingsStore } from "@/lib/store/settings-store";
import { auditLog } from "@/lib/store/audit-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

function mask(value: string | undefined, keep = 6): string {
  if (!value) return "";
  if (value.length <= keep) return "••••••";
  return `••••••${value.slice(-keep)}`;
}

export async function GET() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const snapshot = await settingsStore().get();
  const redacted = {
    ...snapshot,
    adminUsers: snapshot.adminUsers.map((u) => ({ ...u, passwordHash: "[redacted]" })),
    adminTokens: snapshot.adminTokens.map((t) => ({ ...t, value: mask(t.value) })),
  };
  return jsonResponse(200, redacted);
}

export async function PATCH(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const patch = await req.json();
  const before = await settingsStore().get();
  await settingsStore().update(patch);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "settings.update",
    before,
    after: patch,
  });
  return jsonResponse(200, { ok: true });
}
