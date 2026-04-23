"use client";
import * as React from "react";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Card, CardContent, CardHeader, CardTitle, Segmented, Button, Icon, Tabs } from "@/components/m3";
import type { ActivityEntry } from "@/lib/store/request-log";
import type { AuditEntry } from "@/lib/store/audit-log";

type Range = "1h" | "24h" | "7d" | "30d";
type View = "usage" | "audit" | "diagnostics";

export default function ObservabilityPage() {
  const [view, setView] = React.useState<View>("usage");
  const [range, setRange] = React.useState<Range>("24h");
  const [entries, setEntries] = React.useState<ActivityEntry[]>([]);
  const [audit, setAudit] = React.useState<AuditEntry[]>([]);

  React.useEffect(() => {
    fetch("/api/admin/requests").then((r) => r.json()).then((d) => setEntries(d.requests));
    fetch("/api/admin/audit").then((r) => r.json()).then((d) => setAudit(d.entries));
  }, []);

  const windowMs = range === "1h" ? 3600_000 : range === "24h" ? 86400_000 : range === "7d" ? 7 * 86400_000 : 30 * 86400_000;
  const now = Date.now();
  const windowed = entries.filter((e) => now - new Date(e.timestamp).getTime() < windowMs);

  const bucketCount = range === "1h" ? 12 : range === "24h" ? 24 : range === "7d" ? 7 : 30;
  const bucketSize = windowMs / bucketCount;
  const buckets = new Array(bucketCount).fill(0).map(() => ({ requests: 0, tokens: 0, credits: 0 }));
  for (const e of windowed) {
    const age = now - new Date(e.timestamp).getTime();
    const bucket = Math.min(bucketCount - 1, Math.floor(age / bucketSize));
    buckets[bucketCount - 1 - bucket].requests += 1;
    buckets[bucketCount - 1 - bucket].tokens += (e.inputTokens ?? 0) + (e.outputTokens ?? 0);
    buckets[bucketCount - 1 - bucket].credits += e.settledCredits ?? e.reservedCredits ?? 0;
  }

  const errorByPath = new Map<string, number>();
  for (const e of windowed.filter((e) => e.level === "error")) {
    errorByPath.set(e.path ?? "—", (errorByPath.get(e.path ?? "—") ?? 0) + 1);
  }

  return (
    <AdminShell title="Observability" breadcrumb={["Relay"]}>
      <div className="space-y-4 p-6">
        <Tabs
          value={view}
          onChange={setView}
          options={[
            { value: "usage", label: "Usage" },
            { value: "audit", label: "Audit log" },
            { value: "diagnostics", label: "Diagnostics" },
          ]}
        />

        {view === "usage" && (
          <>
            <div className="flex items-center gap-3">
              <Segmented
                value={range}
                onChange={setRange}
                options={[
                  { value: "1h", label: "1h" },
                  { value: "24h", label: "24h" },
                  { value: "7d", label: "7d" },
                  { value: "30d", label: "30d" },
                ]}
              />
            </div>

            <div className="grid gap-4 md:grid-cols-3">
              <BarChart title="Requests" buckets={buckets.map((b) => b.requests)} />
              <BarChart title="Tokens" buckets={buckets.map((b) => b.tokens)} />
              <BarChart title="Credits" buckets={buckets.map((b) => b.credits)} />
            </div>

            <Card>
              <CardHeader>
                <CardTitle>错误分布</CardTitle>
              </CardHeader>
              <CardContent>
                {errorByPath.size === 0 ? (
                  <div className="py-6 text-center text-on-surface-variant">没有错误，棒！</div>
                ) : (
                  <ul className="space-y-2">
                    {Array.from(errorByPath.entries()).map(([path, count]) => (
                      <li key={path} className="flex items-center gap-3 text-m3-body-m">
                        <span className="font-mono">{path}</span>
                        <span className="ml-auto"><Badge tone="error">{count}</Badge></span>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          </>
        )}

        {view === "audit" && (
          <Card>
            <CardContent className="p-0">
              <table className="w-full text-left text-m3-body-s">
                <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
                  <tr>
                    <th className="px-3 py-2">时间</th>
                    <th className="px-3 py-2">操作</th>
                    <th className="px-3 py-2">操作人</th>
                    <th className="px-3 py-2">IP</th>
                    <th className="px-3 py-2">Hash</th>
                  </tr>
                </thead>
                <tbody>
                  {audit.length === 0 && (
                    <tr><td colSpan={5} className="px-3 py-8 text-center text-on-surface-variant">无审计记录</td></tr>
                  )}
                  {audit.map((e) => (
                    <tr key={e.id} className="border-t border-outline-variant">
                      <td className="px-3 py-2">{new Date(e.timestamp).toLocaleString()}</td>
                      <td className="px-3 py-2 font-mono">{e.action}</td>
                      <td className="px-3 py-2">{e.actor} <Badge>{e.role}</Badge></td>
                      <td className="px-3 py-2 text-on-surface-variant">{e.ip ?? "—"}</td>
                      <td className="px-3 py-2 font-mono text-m3-label-s text-on-surface-variant">{e.hash.slice(0, 10)}…</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent>
          </Card>
        )}

        {view === "diagnostics" && (
          <Card className="p-6">
            <CardTitle>诊断包</CardTitle>
            <p className="mt-2 text-m3-body-m text-on-surface-variant">
              下载脱敏后的 activity log + debug log + settings 快照 + audit 链，适合给支持团队排障。
            </p>
            <div className="mt-4 flex gap-3">
              <Button icon="download" onClick={() => window.open("/api/admin/requests")}>下载 requests JSON</Button>
              <Button icon="download" variant="outlined" onClick={() => window.open("/api/admin/audit")}>下载 audit JSON</Button>
              <Button icon="download" variant="outlined" onClick={() => window.open("/api/admin/metrics/prometheus")}>Prometheus metrics</Button>
            </div>
          </Card>
        )}
      </div>
    </AdminShell>
  );
}

function BarChart({ title, buckets }: { title: string; buckets: number[] }) {
  const max = Math.max(...buckets, 1);
  return (
    <Card className="p-4">
      <div className="text-m3-label-m text-on-surface-variant">{title}</div>
      <div className="mt-3 flex h-32 items-end gap-1">
        {buckets.map((v, i) => (
          <div
            key={i}
            className="flex-1 rounded-t-sm bg-primary-container"
            style={{ height: `${(v / max) * 100}%`, minHeight: v > 0 ? "4px" : "1px" }}
            title={`${v}`}
          />
        ))}
      </div>
      <div className="mt-2 text-m3-label-s text-on-surface-variant">
        合计 {buckets.reduce((a, b) => a + b, 0).toLocaleString()}
      </div>
    </Card>
  );
}
