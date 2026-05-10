import Link from "next/link";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import LinearProgress from "@mui/material/LinearProgress";
import { KpiCard } from "@/components/kpi-card";
import { LaunchChecklist, type ChecklistItem } from "@/components/launch-checklist";
import { configDiagnostics } from "@/lib/config";
import { billingStore } from "@/lib/store/billing-store";
import { requestLog } from "@/lib/store/request-log";
import { metrics } from "@/lib/observability/metrics";

export const dynamic = "force-dynamic";

function formatNumber(n: number): string {
  if (!Number.isFinite(n)) return "0";
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(Math.round(n));
}

function formatPercent(n: number): string {
  return `${(n * 100).toFixed(1)}%`;
}

function relTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const s = Math.floor(diff / 1000);
  if (s < 60) return `${s}s 前`;
  if (s < 3600) return `${Math.floor(s / 60)}m 前`;
  if (s < 86400) return `${Math.floor(s / 3600)}h 前`;
  return `${Math.floor(s / 86400)}d 前`;
}

function levelTone(level: string): "default" | "success" | "warning" | "error" | "info" {
  if (level === "error") return "error";
  if (level === "warning") return "warning";
  if (level === "success") return "success";
  return "info";
}

export default async function DashboardPage() {
  const billing = await billingStore().listAll();
  const activity = await requestLog().listActivity();
  const diag = configDiagnostics();
  const snapshot = metrics().snapshot();

  const now = Date.now();
  const last24h = activity.filter((a) => now - new Date(a.timestamp).getTime() < 86_400_000);
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
  const topModelMax = topModels[0]?.credits ?? 0;

  const sparkBuckets = 24;
  const buckets = new Array(sparkBuckets).fill(0);
  for (const a of last24h) {
    const age = (now - new Date(a.timestamp).getTime()) / 3_600_000;
    const idx = sparkBuckets - 1 - Math.min(sparkBuckets - 1, Math.floor(age));
    if (idx >= 0) buckets[idx] += 1;
  }

  const checklist: ChecklistItem[] = [
    {
      id: "gemini",
      label: "上游 Gemini API Key",
      helper: diag.geminiConfigured ? "已配置" : "请在 .env 中设置 GEMINI_API_KEY",
      done: diag.geminiConfigured,
    },
    {
      id: "bearer",
      label: "客户端 Bearer Token",
      helper: diag.bearerConfigured ? "已配置" : "请设置 RELAY_BEARER_TOKEN",
      done: diag.bearerConfigured,
    },
    {
      id: "session",
      label: "会话签名密钥",
      helper: diag.sessionSecretConfigured ? "已配置" : "请设置 RELAY_SESSION_SECRET",
      done: diag.sessionSecretConfigured,
    },
    {
      id: "traffic",
      label: "首条客户端流量",
      helper: activity.length > 0 ? "已收到流量" : "等待客户端首次连接…",
      done: activity.length > 0,
      href: "/requests",
    },
  ];

  return (
    <>
      <Stack spacing={3}>
        <Box
          sx={{
            display: "grid",
            gridTemplateColumns: { xs: "1fr", lg: "1fr 2fr" },
            gap: 3,
          }}
        >
          <LaunchChecklist items={checklist} />
          <Box
            sx={{
              display: "grid",
              gridTemplateColumns: { xs: "1fr 1fr", md: "repeat(4, 1fr)" },
              gap: 2,
            }}
          >
            <KpiCard
              label="24h 请求"
              value={formatNumber(last24h.length)}
              helper={`累计 ${formatNumber(activity.length)}`}
              sparkline={buckets}
            />
            <KpiCard
              label="Token 入 / 出"
              value={`${formatNumber(inputTokens)}/${formatNumber(outputTokens)}`}
              helper="24 小时累计"
            />
            <KpiCard
              label="延迟 p50/p95"
              value={`${Math.round(snapshot.p50Latency)}/${Math.round(snapshot.p95Latency)}ms`}
              helper="最近请求延迟"
            />
            <KpiCard
              label="错误率"
              value={formatPercent(last24h.length ? errorCount / last24h.length : 0)}
              delta={
                last24h.length && errorCount / last24h.length > 0.05
                  ? { tone: "negative", text: "高于阈值" }
                  : { tone: "neutral", text: "正常" }
              }
              helper={`${errorCount} 条错误`}
            />
          </Box>
        </Box>

        <Box
          sx={{
            display: "grid",
            gridTemplateColumns: { xs: "1fr", lg: "2fr 1fr" },
            gap: 3,
          }}
        >
          <Card>
            <CardHeader title="系统状态" />
            <CardContent>
              <Stack spacing={1.5}>
                <Stack direction="row" justifyContent="space-between">
                  <Typography variant="body2">账户总数</Typography>
                  <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
                    {billing.accounts.length}
                  </Typography>
                </Stack>
                <Stack direction="row" justifyContent="space-between">
                  <Typography variant="body2">激活密钥</Typography>
                  <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
                    {billing.keys.filter((k) => k.state === "active").length}
                  </Typography>
                </Stack>
                <Stack direction="row" justifyContent="space-between">
                  <Typography variant="body2">绑定设备</Typography>
                  <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
                    {billing.devices.length}
                  </Typography>
                </Stack>
                <Stack direction="row" justifyContent="space-between">
                  <Typography variant="body2">未使用激活码</Typography>
                  <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
                    {billing.activationCodes.filter((c) => c.state === "unused").length}
                  </Typography>
                </Stack>
                <Stack direction="row" justifyContent="space-between">
                  <Typography variant="body2">数据目录</Typography>
                  <Typography
                    variant="body2"
                    sx={{ fontFamily: "var(--font-mono)", color: "text.secondary" }}
                  >
                    {diag.dataDir}
                  </Typography>
                </Stack>
                <Stack direction="row" justifyContent="space-between">
                  <Typography variant="body2">计费模式</Typography>
                  <Chip
                    size="small"
                    label={diag.billingMode}
                    color={diag.billingMode === "strict" ? "primary" : "default"}
                  />
                </Stack>
              </Stack>
            </CardContent>
          </Card>

          <Card>
            <CardHeader title="模型用量 24h" subheader="按结算 credits 排序" />
            <CardContent>
              {topModels.length === 0 ? (
                <Typography variant="body2" color="text.secondary">
                  暂无数据
                </Typography>
              ) : (
                <Stack spacing={1.5}>
                  {topModels.map((m) => (
                    <Box key={m.modelID}>
                      <Stack direction="row" justifyContent="space-between" sx={{ mb: 0.5 }}>
                        <Typography
                          variant="body2"
                          sx={{ fontFamily: "var(--font-mono)" }}
                          noWrap
                        >
                          {m.modelID}
                        </Typography>
                        <Typography
                          variant="body2"
                          sx={{ fontFamily: "var(--font-mono)" }}
                        >
                          {formatNumber(m.credits)}
                        </Typography>
                      </Stack>
                      <LinearProgress
                        variant="determinate"
                        value={topModelMax > 0 ? (m.credits / topModelMax) * 100 : 0}
                      />
                      <Typography variant="caption" color="text.secondary">
                        {m.requests} 次请求
                      </Typography>
                    </Box>
                  ))}
                </Stack>
              )}
            </CardContent>
          </Card>
        </Box>

        <Card>
          <CardHeader
            title="最近活动"
            action={
              <Typography
                component={Link}
                href="/requests"
                variant="body2"
                sx={{ color: "primary.main", textDecoration: "none", fontWeight: 600 }}
              >
                查看全部 →
              </Typography>
            }
          />
          <CardContent sx={{ p: 0, "&:last-child": { pb: 0 } }}>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>时间</TableCell>
                  <TableCell>等级</TableCell>
                  <TableCell>路径</TableCell>
                  <TableCell>状态</TableCell>
                  <TableCell>账户</TableCell>
                  <TableCell align="right">延迟</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {activity.slice(0, 10).length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={6}>
                      <Typography
                        variant="body2"
                        color="text.secondary"
                        sx={{ textAlign: "center", py: 3 }}
                      >
                        暂无活动
                      </Typography>
                    </TableCell>
                  </TableRow>
                ) : (
                  activity.slice(0, 10).map((row) => (
                    <TableRow key={row.id} hover>
                      <TableCell sx={{ color: "text.secondary" }}>
                        {relTime(row.timestamp)}
                      </TableCell>
                      <TableCell>
                        <Chip size="small" label={row.level} color={levelTone(row.level)} />
                      </TableCell>
                      <TableCell sx={{ fontFamily: "var(--font-mono)", fontSize: "0.8125rem" }}>
                        {row.method ? `${row.method} ` : ""}
                        {row.path ?? row.message}
                      </TableCell>
                      <TableCell sx={{ fontFamily: "var(--font-mono)" }}>
                        {row.statusCode ?? "—"}
                      </TableCell>
                      <TableCell>
                        <Typography
                          variant="body2"
                          sx={{ fontFamily: "var(--font-mono)" }}
                          noWrap
                        >
                          {row.accountName ?? row.accountID ?? "—"}
                        </Typography>
                      </TableCell>
                      <TableCell align="right" sx={{ fontFamily: "var(--font-mono)" }}>
                        {row.latencyMs != null ? `${row.latencyMs}ms` : "—"}
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Typography variant="caption" color="text.secondary">
          可用额度合计 {formatNumber(totalCredits)} credits
        </Typography>
      </Stack>
    </>
  );
}
