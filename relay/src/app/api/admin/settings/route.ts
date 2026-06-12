import { requireAdmin } from "@/lib/auth/admin-guard";
import { settingsStore, type SettingsSnapshot } from "@/lib/store/settings-store";
import { auditLog, sanitizeAuditPayload } from "@/lib/store/audit-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

function publicSettingsSnapshot(snapshot: SettingsSnapshot): SettingsSnapshot {
  return {
    ...snapshot,
    adminUsers: snapshot.adminUsers.map((user) => ({
      ...user,
      passwordHash: "[redacted]",
    })),
    adminTokens: snapshot.adminTokens.map((token) => ({
      ...token,
      value: "[redacted]",
    })),
  };
}

export async function GET() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const snapshot = await settingsStore().get();
  return jsonResponse(200, publicSettingsSnapshot(snapshot));
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
