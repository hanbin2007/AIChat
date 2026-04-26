import { requireAdmin } from "@/lib/auth/admin-guard";
import { requestLog } from "@/lib/store/request-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;

  const url = new URL(req.url);
  const level = url.searchParams.get("level");
  const category = url.searchParams.get("category");
  const path = url.searchParams.get("path");
  const query = url.searchParams.get("q")?.toLowerCase();
  const since = url.searchParams.get("since");

  let list = await requestLog().listActivity();
  if (level) list = list.filter((e) => e.level === level);
  if (category) list = list.filter((e) => e.category === category);
  if (path) list = list.filter((e) => e.path === path);
  if (since) {
    const cutoff = Date.now() - Number(since);
    list = list.filter((e) => new Date(e.timestamp).getTime() > cutoff);
  }
  if (query) {
    list = list.filter(
      (e) =>
        e.message.toLowerCase().includes(query) ||
        e.path?.toLowerCase().includes(query) ||
        e.accountID?.toLowerCase().includes(query) ||
        e.deviceID?.toLowerCase().includes(query) ||
        e.modelID?.toLowerCase().includes(query),
    );
  }
  return jsonResponse(200, { requests: list.slice(0, 200) });
}

export async function DELETE() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  await requestLog().clearActivity();
  return jsonResponse(200, { ok: true });
}
