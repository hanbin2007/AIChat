import { requireOperator } from "@/lib/auth/admin-guard";
import { conversationPins } from "@/lib/store/conversation-pins";
import { auditLog } from "@/lib/store/audit-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function POST(req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireOperator();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  const body = (await req.json().catch(() => ({}))) as { note?: string };
  await conversationPins().pin(id, body.note);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "conversation.pin",
    target: id,
  });
  return jsonResponse(200, { ok: true, pinned: true });
}

export async function DELETE(_req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireOperator();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  await conversationPins().unpin(id);
  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "conversation.unpin",
    target: id,
  });
  return jsonResponse(200, { ok: true, pinned: false });
}
