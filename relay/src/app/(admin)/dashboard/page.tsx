import Link from "next/link";
import { AdminShell } from "@/components/admin-shell";
import { KpiCard } from "@/components/kpi-card";
import { LaunchChecklist } from "@/components/launch-checklist";
import { Badge, Card, CardContent, CardHeader, CardTitle, Icon } from "@/components/m3";
import { config, configDiagnostics } from "@/lib/config";
import { billingStore } from "@/lib/store/billing-store";
import { requestLog } from "@/lib/store/request-log";
import { metrics } from "@/lib/observability/metrics";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const diag = configDiagnostics();
  const billing = await billingStore().listAll();
  const activity = await requestLog().listActivity();
  const now = Date.now();
  const last24h = activity.filter((a) => now - new Date(a.timestamp).getTime() < 86400_000);
  const errors24h = last24h.filter((a) => a.level === "error").length;
  const reqPerHour = bucketByHour(last24h.map((a) => a.timestamp));
  const totalCredits = billing.accounts.reduce((s, a) => s + a.creditBalance, 0);
  const inputTokens = last24h.reduce((s, a) => s + (a.inputTokens ?? 0), 0);
  const outputTokens = last24h.reduce((s, a) => s + (a.outputTokens ?? 0), 0);
  const snapshot = metrics().snapshot();

  const checklist = [
    {
      id: "gemini",
      label: "Gemini API key 已配置",
      description: diag.geminiConfigured ? "已在启动环境中注入" : "在 .env 中设置 GEMINI_API_KEY",
      done: diag.geminiConfigured,
      href: "/settings",
    },
    {
      id: "bearer",
      label: "Relay bearer token 已签发",
      description: diag.bearerConfigured ? "RELAY_BEARER_TOKEN 生效中" : "缺少 RELAY_BEARER_TOKEN；客户端将被拒绝",
      done: diag.bearerConfigured,
      href: "/settings",
    },
    {
      id: "listener",
      label: "Listener 在线",
      description: `正在 0.0.0.0:${config.port} 接受请求`,
      done: true,
    },
    {
      id: "traffic",
      label: "首笔流量已到达",
      description: activity.length > 0 ? `已处理 ${activity.length} 次请求` : "等待客户端第一次调用",
      done: activity.length > 0,
      href: "/requests",
    },
  ];

  const topModels = last24h.reduce<Record<string, { requests: number; credits: number }>>((acc, a) => {
    if (!a.modelID) return acc;
    acc[a.modelID] ??= { requests: 0, credits: 0 };
    acc[a.modelID].requests += 1;
    acc[a.modelID].credits += a.settledCredits ?? a.reservedCredits ?? 0;
    return acc;
  }, {});

  const topModelEntries = Object.entries(topModels)
    .sort((a, b) => b[1].credits - a[1].credits)
    .slice(0, 5);

  return (
    <AdminShell title="Dashboard" breadcrumb={["Relay"]}>
      <div className="space-y-6 p-6">
        <LaunchChecklist items={checklist} />

        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
          <KpiCard
            label="24h 请求数"
            value={last24h.length.toLocaleString()}
            helper={`${billing.accounts.length} 个账户 · ${billing.keys.filter((k) => k.state === "active").length} 把活跃 key`}
            spark={reqPerHour}
          />
          <KpiCard
            label="Token in / out"
            value={`${formatNumber(inputTokens)} / ${formatNumber(outputTokens)}`}
            helper="24 小时累计"
          />
          <KpiCard
            label="延迟 p50 / p95"
            value={`${Math.round(snapshot.p50Latency)}ms / ${Math.round(snapshot.p95Latency)}ms`}
            helper="仅统计 /chat/stream"
          />
          <KpiCard
            label="错误率"
            value={`${last24h.length ? ((errors24h / last24h.length) * 100).toFixed(1) : "0.0"}%`}
            tone={errors24h === 0 ? "positive" : "negative"}
            helper={`错误 ${errors24h} / ${last24h.length}`}
          />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>系统状态</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <Status label="Gemini API key" ok={diag.geminiConfigured} />
              <Status label="Bearer token" ok={diag.bearerConfigured} />
              <Status label="Session secret" ok={diag.sessionSecretConfigured} />
              <Status label="Listener" ok={true} detail={`0.0.0.0:${config.port}`} />
              <Status label="数据目录" ok={true} detail={diag.dataDir} />
              <Status label="Billing mode" ok={true} detail={diag.billingMode} />
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Top Models (24h)</CardTitle>
            </CardHeader>
            <CardContent>
              {topModelEntries.length === 0 ? (
                <div className="py-6 text-center text-m3-body-m text-on-surface-variant">
                  <Icon name="bar_chart" size={32} className="opacity-50" />
                  <div className="mt-2">等待第一次请求</div>
                </div>
              ) : (
                <ul className="space-y-3">
                  {topModelEntries.map(([model, v]) => (
                    <li key={model} className="flex items-center gap-3">
                      <Icon name="neurology" size={20} className="text-on-surface-variant" />
                      <div className="flex-1 min-w-0">
                        <div className="truncate text-m3-body-m">{model}</div>
                        <div className="text-m3-body-s text-on-surface-variant">{v.requests} 次</div>
                      </div>
                      <Badge tone="info">{formatNumber(v.credits)} credits</Badge>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <div className="flex items-baseline justify-between">
              <CardTitle>最近活动</CardTitle>
              <Link href="/requests" className="text-m3-label-l text-primary hover:underline">
                查看全部 →
              </Link>
            </div>
          </CardHeader>
          <CardContent>
            {activity.length === 0 ? (
              <div className="py-8 text-center text-m3-body-m text-on-surface-variant">
                尚无记录
              </div>
            ) : (
              <div className="overflow-hidden rounded-m3-sm border border-outline-variant">
                <table className="w-full text-left text-m3-body-s">
                  <thead className="bg-surface-container-low">
                    <tr>
                      <th className="px-3 py-2 font-medium">时间</th>
                      <th className="px-3 py-2 font-medium">端点</th>
                      <th className="px-3 py-2 font-medium">状态</th>
                      <th className="px-3 py-2 font-medium">延迟</th>
                      <th className="px-3 py-2 font-medium">模型</th>
                      <th className="px-3 py-2 font-medium">Credits</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activity.slice(0, 10).map((a) => (
                      <tr key={a.id} className="border-t border-outline-variant">
                        <td className="px-3 py-2 text-on-surface-variant">
                          {new Date(a.timestamp).toLocaleTimeString()}
                        </td>
                        <td className="px-3 py-2 font-mono">{a.path}</td>
                        <td className="px-3 py-2">
                          <Badge tone={a.level === "error" ? "error" : a.level === "warning" ? "warn" : "success"}>
                            {a.statusCode ?? "—"}
                          </Badge>
                        </td>
                        <td className="px-3 py-2">{a.latencyMs ?? 0}ms</td>
                        <td className="px-3 py-2">{a.modelID ?? "—"}</td>
                        <td className="px-3 py-2">{a.settledCredits ?? a.reservedCredits ?? "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>

        <div className="text-center text-m3-body-s text-on-surface-variant">
          总额度：{totalCredits.toLocaleString()} credits
        </div>
      </div>
    </AdminShell>
  );
}

function Status({ label, ok, detail }: { label: string; ok: boolean; detail?: string }) {
  return (
    <div className="flex items-center gap-3">
      <Icon
        name={ok ? "check_circle" : "cancel"}
        filled
        size={22}
        className={ok ? "text-primary" : "text-error"}
      />
      <div className="flex-1">
        <div className="text-m3-body-m">{label}</div>
        {detail && <div className="text-m3-body-s text-on-surface-variant">{detail}</div>}
      </div>
      <Badge tone={ok ? "success" : "error"}>{ok ? "OK" : "Missing"}</Badge>
    </div>
  );
}

function bucketByHour(timestamps: string[]): number[] {
  const buckets = new Array(24).fill(0);
  const now = Date.now();
  for (const t of timestamps) {
    const age = now - new Date(t).getTime();
    const hour = Math.floor(age / 3600_000);
    if (hour >= 0 && hour < 24) buckets[23 - hour] += 1;
  }
  return buckets;
}

function formatNumber(n: number): string {
  if (n > 1e9) return `${(n / 1e9).toFixed(1)}B`;
  if (n > 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n > 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toLocaleString();
}
