import { requireAdmin } from "@/lib/auth/admin-guard";
import { metrics } from "@/lib/observability/metrics";
import { billingStore } from "@/lib/store/billing-store";
import { requestLog } from "@/lib/store/request-log";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;

  const billing = await billingStore().listAll();
  const activity = await requestLog().listActivity();
  const now = Date.now();
  const last24h = activity.filter((a) => now - new Date(a.timestamp).getTime() < 86400_000);
  const errorCount = last24h.filter((a) => a.level === "error").length;
  const inputTokens = last24h.reduce((s, a) => s + (a.inputTokens ?? 0), 0);
  const outputTokens = last24h.reduce((s, a) => s + (a.outputTokens ?? 0), 0);
  const totalCredits = billing.accounts.reduce((s, a) => s + a.creditBalance, 0);

  const byModel = new Map<string, { requests: number; credits: number }>();
  for (const a of last24h) {
    if (!a.modelID) continue;
    const prev = byModel.get(a.modelID) ?? { requests: 0, credits: 0 };
    prev.requests += 1;
    prev.credits += a.settledCredits ?? a.reservedCredits ?? 0;
    byModel.set(a.modelID, prev);
  }
  const topModels = Array.from(byModel.entries())
    .map(([modelID, v]) => ({ modelID, ...v }))
    .sort((a, b) => b.credits - a.credits)
    .slice(0, 5);

  const snapshot = metrics().snapshot();

  return jsonResponse(200, {
    accounts: billing.accounts.length,
    activeKeys: billing.keys.filter((k) => k.state === "active").length,
    totalCredits,
    requests24h: last24h.length,
    errorRate: last24h.length ? errorCount / last24h.length : 0,
    inputTokens24h: inputTokens,
    outputTokens24h: outputTokens,
    p50Latency: snapshot.p50Latency,
    p95Latency: snapshot.p95Latency,
    topModels,
    recent: activity.slice(0, 10),
  });
}
