import { requireAdmin } from "@/lib/auth/admin-guard";
import { listConversations } from "@/lib/store/conversations";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const url = new URL(req.url);
  const conversations = await listConversations({
    limit: Number(url.searchParams.get("limit") ?? 100),
    accountID: url.searchParams.get("accountID") ?? undefined,
    deviceID: url.searchParams.get("deviceID") ?? undefined,
    modelID: url.searchParams.get("modelID") ?? undefined,
    hasErrors: url.searchParams.get("hasErrors") === "1" || undefined,
    hasImages: url.searchParams.get("hasImages") === "1" || undefined,
    hasAudio: url.searchParams.get("hasAudio") === "1" || undefined,
    pinnedOnly: url.searchParams.get("pinned") === "1" || undefined,
    query: url.searchParams.get("q") ?? undefined,
  });
  return jsonResponse(200, { conversations });
}
