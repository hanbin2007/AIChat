import { requireAdmin } from "@/lib/auth/admin-guard";
import { settingsStore } from "@/lib/store/settings-store";
import { auditLog } from "@/lib/store/audit-log";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const body = (await req.json().catch(() => null)) as {
    label?: string;
    scope?: "admin" | "client";
    rpmLimit?: number;
    expiresAt?: string;
  } | null;
  if (!body?.label || !body?.scope) return errorResponse(400, "label + scope required.");
  const token = await settingsStore().issueToken({
    label: body.label,
    scope: body.scope,
    rpmLimit: body.rpmLimit,
    expiresAt: body.expiresAt,
  });
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "tokens.issue",
    target: token.id,
  });
  return jsonResponse(200, token);
}

export async function DELETE(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const url = new URL(req.url);
  const id = url.searchParams.get("id");
  if (!id) return errorResponse(400, "id required.");
  await settingsStore().revokeToken(id);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "tokens.revoke",
    target: id,
  });
  return jsonResponse(200, { ok: true });
}
