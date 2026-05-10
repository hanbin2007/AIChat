import Link from "next/link";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import Grid from "@mui/material/Grid2";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import Chip from "@mui/material/Chip";
import MuiLink from "@mui/material/Link";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import Paper from "@mui/material/Paper";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import CancelIcon from "@mui/icons-material/Cancel";
import BarChartIcon from "@mui/icons-material/BarChart";
import NeurologyIcon from "@mui/icons-material/Psychology";
import { AppShell } from "@/components/shell/app-shell";
import { KpiCard } from "@/components/kpi-card";
import { LaunchChecklist } from "@/components/launch-checklist";
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
    <AppShell title="Dashboard" breadcrumb={["Relay"]}>
      <Box sx={{ p: 3 }}>
        <Stack spacing={3}>
          <LaunchChecklist items={checklist} />

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, md: 6, xl: 3 }}>
              <KpiCard
                label="24h 请求数"
                value={last24h.length.toLocaleString()}
                helper={`${billing.accounts.length} 个账户 · ${billing.keys.filter((k) => k.state === "active").length} 把活跃 key`}
                spark={reqPerHour}
              />
            </Grid>
            <Grid size={{ xs: 12, md: 6, xl: 3 }}>
              <KpiCard
                label="Token in / out"
                value={`${formatNumber(inputTokens)} / ${formatNumber(outputTokens)}`}
                helper="24 小时累计"
              />
            </Grid>
            <Grid size={{ xs: 12, md: 6, xl: 3 }}>
              <KpiCard
                label="延迟 p50 / p95"
                value={`${Math.round(snapshot.p50Latency)}ms / ${Math.round(snapshot.p95Latency)}ms`}
                helper="仅统计 /chat/stream"
              />
            </Grid>
            <Grid size={{ xs: 12, md: 6, xl: 3 }}>
              <KpiCard
                label="错误率"
                value={`${last24h.length ? ((errors24h / last24h.length) * 100).toFixed(1) : "0.0"}%`}
                tone={errors24h === 0 ? "positive" : "negative"}
                helper={`错误 ${errors24h} / ${last24h.length}`}
              />
            </Grid>
          </Grid>

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, lg: 8 }}>
              <Card>
                <CardHeader title="系统状态" titleTypographyProps={{ variant: "subtitle1" }} />
                <CardContent>
                  <Stack spacing={1.5}>
                    <Status label="Gemini API key" ok={diag.geminiConfigured} />
                    <Status label="Bearer token" ok={diag.bearerConfigured} />
                    <Status label="Session secret" ok={diag.sessionSecretConfigured} />
                    <Status label="Listener" ok detail={`0.0.0.0:${config.port}`} />
                    <Status label="数据目录" ok detail={diag.dataDir} />
                    <Status label="Billing mode" ok detail={diag.billingMode} />
                  </Stack>
                </CardContent>
              </Card>
            </Grid>
            <Grid size={{ xs: 12, lg: 4 }}>
              <Card sx={{ height: "100%" }}>
                <CardHeader title="Top Models (24h)" titleTypographyProps={{ variant: "subtitle1" }} />
                <CardContent>
                  {topModelEntries.length === 0 ? (
                    <Stack alignItems="center" sx={{ py: 3, color: "text.secondary" }}>
                      <BarChartIcon sx={{ opacity: 0.5, fontSize: 32 }} />
                      <Typography variant="body2" sx={{ mt: 1 }}>
                        等待第一次请求
                      </Typography>
                    </Stack>
                  ) : (
                    <List dense disablePadding>
                      {topModelEntries.map(([model, v]) => (
                        <ListItem key={model} disableGutters secondaryAction={<Chip size="small" label={`${formatNumber(v.credits)} credits`} color="info" />}>
                          <ListItemIcon sx={{ minWidth: 32 }}>
                            <NeurologyIcon fontSize="small" color="action" />
                          </ListItemIcon>
                          <ListItemText
                            primary={model}
                            secondary={`${v.requests} 次`}
                            primaryTypographyProps={{ variant: "body2", noWrap: true }}
                            secondaryTypographyProps={{ variant: "caption" }}
                          />
                        </ListItem>
                      ))}
                    </List>
                  )}
                </CardContent>
              </Card>
            </Grid>
          </Grid>

          <Card>
            <CardHeader
              title="最近活动"
              titleTypographyProps={{ variant: "subtitle1" }}
              action={
                <MuiLink component={Link} href="/requests" variant="body2" underline="hover">
                  查看全部 →
                </MuiLink>
              }
            />
            <CardContent>
              {activity.length === 0 ? (
                <Typography variant="body2" align="center" sx={{ py: 4, color: "text.secondary" }}>
                  尚无记录
                </Typography>
              ) : (
                <TableContainer component={Paper} variant="outlined">
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>时间</TableCell>
                        <TableCell>端点</TableCell>
                        <TableCell>状态</TableCell>
                        <TableCell>延迟</TableCell>
                        <TableCell>模型</TableCell>
                        <TableCell>Credits</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {activity.slice(0, 10).map((a) => (
                        <TableRow key={a.id} hover>
                          <TableCell sx={{ color: "text.secondary" }}>
                            {new Date(a.timestamp).toLocaleTimeString()}
                          </TableCell>
                          <TableCell sx={{ fontFamily: "monospace" }}>{a.path}</TableCell>
                          <TableCell>
                            <Chip
                              size="small"
                              color={a.level === "error" ? "error" : a.level === "warning" ? "warning" : "success"}
                              label={a.statusCode ?? "—"}
                            />
                          </TableCell>
                          <TableCell>{a.latencyMs ?? 0}ms</TableCell>
                          <TableCell>{a.modelID ?? "—"}</TableCell>
                          <TableCell>{a.settledCredits ?? a.reservedCredits ?? "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </TableContainer>
              )}
            </CardContent>
          </Card>

          <Typography variant="caption" align="center" sx={{ color: "text.secondary" }}>
            总额度：{totalCredits.toLocaleString()} credits
          </Typography>
        </Stack>
      </Box>
    </AppShell>
  );
}

function Status({ label, ok, detail }: { label: string; ok: boolean; detail?: string }) {
  return (
    <Box sx={{ display: "flex", alignItems: "center", gap: 1.5 }}>
      {ok ? (
        <CheckCircleIcon color="success" fontSize="small" />
      ) : (
        <CancelIcon color="error" fontSize="small" />
      )}
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography variant="body2">{label}</Typography>
        {detail && (
          <Typography variant="caption" sx={{ color: "text.secondary", wordBreak: "break-all" }}>
            {detail}
          </Typography>
        )}
      </Box>
      <Chip size="small" color={ok ? "success" : "error"} label={ok ? "OK" : "Missing"} />
    </Box>
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
