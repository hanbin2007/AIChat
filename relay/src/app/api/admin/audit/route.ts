import { requireAdmin } from "@/lib/auth/admin-guard";
import { auditLog } from "@/lib/store/audit-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const url = new URL(req.url);
  const limit = Number(url.searchParams.get("limit") ?? 200);
  const entries = await auditLog().list(limit);
  return jsonResponse(200, { entries });
}
