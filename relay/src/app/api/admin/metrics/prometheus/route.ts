import { requireAdmin } from "@/lib/auth/admin-guard";
import { metrics } from "@/lib/observability/metrics";

export const runtime = "nodejs";

export async function GET() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  return new Response(metrics().render(), {
    status: 200,
    headers: { "Content-Type": "text/plain; version=0.0.4" },
  });
}
