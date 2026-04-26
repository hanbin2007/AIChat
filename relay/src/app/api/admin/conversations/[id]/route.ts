import { requireAdmin } from "@/lib/auth/admin-guard";
import { getConversation } from "@/lib/store/conversations";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET(_req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  const conversation = await getConversation(id);
  if (!conversation) return errorResponse(404, "Conversation not found.");
  return jsonResponse(200, { conversation });
}
