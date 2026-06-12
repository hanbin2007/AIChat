"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { ComponentType } from "react";
import dynamic from "next/dynamic";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import ToggleButton from "@mui/material/ToggleButton";
import Button from "@mui/material/Button";
import Chip from "@mui/material/Chip";
import DownloadRounded from "@mui/icons-material/DownloadRounded";
import type { DataGridProps, GridColDef } from "@mui/x-data-grid";
import { useSnackbar } from "@/components/snackbar-provider";
import type { ActivityEntry } from "@/lib/store/request-log";
import type { AuditEntry } from "@/lib/store/audit-log";

type TabKey = "usage" | "audit" | "diag";
type Range = "1h" | "24h" | "7d" | "30d";
type LoadState = "loading" | "ready" | "error";

const DataGrid = dynamic(() => import("@mui/x-data-grid").then((mod) => mod.DataGrid), {
  ssr: false,
  loading: () => <StatusPanel message="正在加载审计表格…" />,
}) as ComponentType<DataGridProps<AuditEntry>>;

const RANGE_MS: Record<Range, number> = {
  "1h": 3_600_000,
  "24h": 86_400_000,
  "7d": 7 * 86_400_000,
  "30d": 30 * 86_400_000,
};
const REDACTED = "[redacted]";

function shouldRedactField(key: string): boolean {
  const normalized = key.toLowerCase();
  return normalized.includes("token") || normalized.includes("key") || normalized.includes("password");
}

function sanitizeExportPayload<T>(value: T): T {
  if (Array.isArray(value)) return value.map((item) => sanitizeExportPayload(item)) as T;
  if (!value || typeof value !== "object") return value;

  const output: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (key === "adminTokens" && Array.isArray(item)) {
      output[key] = item.map((token) => {
        if (!token || typeof token !== "object" || Array.isArray(token)) return sanitizeExportPayload(token);
        return { ...(sanitizeExportPayload(token) as Record<string, unknown>), value: REDACTED };
      });
    } else if (key === "value" && "prefix" in (value as Record<string, unknown>) && "scope" in (value as Record<string, unknown>)) {
      output[key] = REDACTED;
    } else if (shouldRedactField(key)) {
      output[key] = REDACTED;
    } else {
      output[key] = sanitizeExportPayload(item);
    }
  }
  return output as T;
}

function downloadJson(filename: string, payload: unknown) {
  const blob = new Blob([JSON.stringify(sanitizeExportPayload(payload), null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

export default function ObservabilityPage() {
  const snackbar = useSnackbar();
  const [tab, setTab] = useState<TabKey>("usage");
  const [range, setRange] = useState<Range>("24h");
  const [activity, setActivity] = useState<ActivityEntry[]>([]);
  const [audit, setAudit] = useState<AuditEntry[]>([]);
  const [activityState, setActivityState] = useState<LoadState>("loading");
  const [auditState, setAuditState] = useState<LoadState>("loading");

  const load = useCallback(async () => {
    try {
      const [r, a] = await Promise.all([
        fetch("/api/admin/requests"),
        fetch("/api/admin/audit"),
      ]);
      if (r.ok) {
        const data = (await r.json()) as { requests: ActivityEntry[] };
        setActivity(data.requests);
        setActivityState("ready");
      } else {
        setActivityState("error");
      }
      if (a.ok) {
        const data = (await a.json()) as { entries: AuditEntry[] };
        setAudit(data.entries);
        setAuditState("ready");
      } else {
        setAuditState("error");
      }
    } catch {
      setActivityState("error");
      setAuditState("error");
      snackbar.push({ message: "拉取观测数据失败", severity: "error" });
    }
  }, [snackbar]);

  useEffect(() => {
    void load();
  }, [load]);

  const buckets = useMemo(() => {
    const now = Date.now();
    const span = RANGE_MS[range];
    const filtered = activity.filter(
      (a) => now - new Date(a.timestamp).getTime() < span,
    );
    const N = 24;
    const reqs = new Array(N).fill(0);
    const tokens = new Array(N).fill(0);
    const credits = new Array(N).fill(0);
    for (const a of filtered) {
      const age = now - new Date(a.timestamp).getTime();
      const idx = N - 1 - Math.min(N - 1, Math.floor((age / span) * N));
      if (idx < 0) continue;
      reqs[idx] += 1;
      tokens[idx] += (a.inputTokens ?? 0) + (a.outputTokens ?? 0);
      credits[idx] += a.settledCredits ?? a.reservedCredits ?? 0;
    }
    return { reqs, tokens, credits, total: filtered.length };
  }, [activity, range]);

  const errorByPath = useMemo(() => {
    const now = Date.now();
    const span = RANGE_MS[range];
    const map = new Map<string, number>();
    for (const a of activity) {
      if (a.level !== "error") continue;
      if (now - new Date(a.timestamp).getTime() > span) continue;
      const key = a.path ?? "(unknown)";
      map.set(key, (map.get(key) ?? 0) + 1);
    }
    return Array.from(map.entries()).sort((a, b) => b[1] - a[1]);
  }, [activity, range]);

  const auditCols = useMemo<GridColDef<AuditEntry>[]>(
    () => [
      {
        field: "timestamp",
        headerName: "时间",
        width: 180,
        valueGetter: (_v, row) => new Date(row.timestamp).toLocaleString("zh-Hans"),
      },
      { field: "action", headerName: "动作", flex: 1, minWidth: 200 },
      {
        field: "actor",
        headerName: "操作者",
        width: 200,
        renderCell: (p) => (
          <Stack direction="row" spacing={1} alignItems="center">
            <span>{p.row.actor}</span>
            <Chip size="small" label={p.row.role} variant="outlined" />
          </Stack>
        ),
      },
      { field: "ip", headerName: "IP", width: 140, valueGetter: (_v, row) => row.ip ?? "—" },
      {
        field: "hash",
        headerName: "哈希",
        width: 140,
        renderCell: (p) => (
          <Typography variant="caption" sx={{ fontFamily: "var(--font-mono)" }}>
            {p.row.hash.slice(0, 10)}
          </Typography>
        ),
      },
    ],
    [],
  );

  return (
    <>
      <Card>
        <Box sx={{ borderBottom: 1, borderColor: "divider" }}>
          <Tabs value={tab} onChange={(_e, v: TabKey) => setTab(v)} variant="scrollable">
            <Tab value="usage" label="用量" />
            <Tab value="audit" label="审计日志" />
            <Tab value="diag" label="诊断" />
          </Tabs>
        </Box>

        <Box sx={{ p: { xs: 2, md: 3 } }}>
          {tab === "usage" ? (
            <Stack spacing={3}>
              <Stack direction="row" justifyContent="space-between" alignItems="center">
                <Typography variant="body2" color="text.secondary">
                  {buckets.total} 条请求
                </Typography>
                <ToggleButtonGroup
                  aria-label="时间范围"
                  exclusive
                  size="small"
                  value={range}
                  onChange={(_e, v: Range | null) => {
                    if (v) setRange(v);
                  }}
                >
                  <ToggleButton value="1h">1h</ToggleButton>
                  <ToggleButton value="24h">24h</ToggleButton>
                  <ToggleButton value="7d">7d</ToggleButton>
                  <ToggleButton value="30d">30d</ToggleButton>
                </ToggleButtonGroup>
              </Stack>

              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", md: "repeat(3, 1fr)" },
                  gap: 2,
                }}
              >
                <ChartCard title="请求" values={buckets.reqs} />
                <ChartCard title="Tokens" values={buckets.tokens} />
                <ChartCard title="Credits" values={buckets.credits} />
              </Box>

              {activityState === "error" ? (
                <StatusPanel message="请求日志加载失败，图表可能不完整。" actionLabel="重试" onAction={() => void load()} />
              ) : null}

              <Card variant="outlined">
                <CardHeader title={`错误分布 · ${range}`} />
                <CardContent>
                  {errorByPath.length === 0 ? (
                    <Typography variant="body2" color="text.secondary">
                      无错误记录
                    </Typography>
                  ) : (
                    <Stack direction="row" spacing={1} flexWrap="wrap">
                      {errorByPath.map(([path, count]) => (
                        <Chip
                          key={path}
                          label={`${path} · ${count}`}
                          variant="outlined"
                          color="error"
                        />
                      ))}
                    </Stack>
                  )}
                </CardContent>
              </Card>
            </Stack>
          ) : null}

          {tab === "audit" ? (
            <Box sx={{ height: 600 }}>
              {auditState === "loading" ? (
                <StatusPanel message="正在加载审计日志…" />
              ) : auditState === "error" ? (
                <StatusPanel message="审计日志加载失败" actionLabel="重试" onAction={() => void load()} />
              ) : (
              <DataGrid
                rows={audit}
                columns={auditCols}
                getRowId={(r) => r.id}
                density="compact"
                sx={{ border: "none" }}
              />
              )}
            </Box>
          ) : null}

          {tab === "diag" ? (
            <Stack spacing={2}>
              <Typography variant="body2" color="text.secondary">
                诊断数据导出
              </Typography>
              <Stack direction="row" spacing={1.5} flexWrap="wrap">
                <Button
                  startIcon={<DownloadRounded />}
                  variant="outlined"
                  onClick={() => downloadJson("relay-requests.json", { requests: activity })}
                >
                  请求日志 JSON
                </Button>
                <Button
                  startIcon={<DownloadRounded />}
                  variant="outlined"
                  onClick={() => downloadJson("relay-audit.json", { entries: audit })}
                >
                  审计 JSON
                </Button>
                <Button
                  startIcon={<DownloadRounded />}
                  variant="outlined"
                  component="a"
                  href="/api/admin/metrics/prometheus"
                  download="relay-metrics.txt"
                >
                  Prometheus 指标
                </Button>
              </Stack>
            </Stack>
          ) : null}
        </Box>
      </Card>
    </>
  );
}

function StatusPanel({
  message,
  actionLabel,
  onAction,
}: {
  message: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <Box sx={{ minHeight: 180, display: "grid", placeItems: "center", p: 3, textAlign: "center" }}>
      <Stack spacing={1.5} alignItems="center">
        <Typography color="text.secondary">{message}</Typography>
        {actionLabel && onAction ? (
          <Button variant="outlined" size="small" onClick={onAction}>
            {actionLabel}
          </Button>
        ) : null}
      </Stack>
    </Box>
  );
}

function ChartCard({ title, values }: { title: string; values: number[] }) {
  const max = Math.max(...values, 1);
  return (
    <Card variant="outlined">
      <CardHeader
        title={
          <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
            {title}
          </Typography>
        }
      />
      <CardContent>
        <Box
          sx={{
            display: "flex",
            alignItems: "flex-end",
            height: 96,
            gap: 0.5,
          }}
        >
          {values.map((v, i) => (
            <Box
              key={i}
              sx={{
                flex: 1,
                height: `${(v / max) * 100}%`,
                bgcolor: "primary.light",
                borderRadius: 0.5,
                minHeight: v > 0 ? 2 : 0,
              }}
              title={`bucket ${i}: ${v}`}
            />
          ))}
        </Box>
        <Typography
          variant="caption"
          color="text.secondary"
          sx={{ display: "block", mt: 1, fontFamily: "var(--font-mono)" }}
        >
          总计 {values.reduce((s, v) => s + v, 0)}
        </Typography>
      </CardContent>
    </Card>
  );
}
