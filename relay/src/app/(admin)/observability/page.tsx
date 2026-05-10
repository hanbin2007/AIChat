"use client";
import * as React from "react";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Chip from "@mui/material/Chip";
import Button from "@mui/material/Button";
import Grid from "@mui/material/Grid2";
import ToggleButton from "@mui/material/ToggleButton";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import { DataGrid, type GridColDef } from "@mui/x-data-grid";
import DownloadIcon from "@mui/icons-material/Download";
import { AppShell } from "@/components/shell/app-shell";
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

  const windowMs =
    range === "1h" ? 3600_000 : range === "24h" ? 86400_000 : range === "7d" ? 7 * 86400_000 : 30 * 86400_000;
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

  const auditColumns: GridColDef<AuditEntry>[] = [
    {
      field: "timestamp",
      headerName: "时间",
      width: 200,
      valueFormatter: (v: string) => new Date(v).toLocaleString(),
    },
    { field: "action", headerName: "操作", width: 200 },
    {
      field: "actor",
      headerName: "操作人",
      width: 200,
      renderCell: (params) => (
        <Stack direction="row" spacing={1} alignItems="center" sx={{ height: "100%" }}>
          <Typography variant="body2">{params.row.actor}</Typography>
          <Chip size="small" label={params.row.role} />
        </Stack>
      ),
    },
    { field: "ip", headerName: "IP", width: 150, valueFormatter: (v: string | undefined) => v ?? "—" },
    {
      field: "hash",
      headerName: "Hash",
      flex: 1,
      renderCell: (params) => (
        <Typography variant="caption" sx={{ fontFamily: "monospace", color: "text.secondary" }}>
          {params.row.hash.slice(0, 10)}…
        </Typography>
      ),
    },
  ];

  return (
    <AppShell title="Observability" breadcrumb={["Relay"]}>
      <Box sx={{ p: 3 }}>
        <Stack spacing={2}>
          <Tabs value={view} onChange={(_, v) => setView(v as View)}>
            <Tab value="usage" label="Usage" />
            <Tab value="audit" label="Audit log" />
            <Tab value="diagnostics" label="Diagnostics" />
          </Tabs>

          {view === "usage" && (
            <>
              <ToggleButtonGroup
                size="small"
                exclusive
                value={range}
                onChange={(_, v) => v && setRange(v as Range)}
              >
                <ToggleButton value="1h">1h</ToggleButton>
                <ToggleButton value="24h">24h</ToggleButton>
                <ToggleButton value="7d">7d</ToggleButton>
                <ToggleButton value="30d">30d</ToggleButton>
              </ToggleButtonGroup>

              <Grid container spacing={2}>
                <Grid size={{ xs: 12, md: 4 }}>
                  <BarChart title="Requests" buckets={buckets.map((b) => b.requests)} />
                </Grid>
                <Grid size={{ xs: 12, md: 4 }}>
                  <BarChart title="Tokens" buckets={buckets.map((b) => b.tokens)} />
                </Grid>
                <Grid size={{ xs: 12, md: 4 }}>
                  <BarChart title="Credits" buckets={buckets.map((b) => b.credits)} />
                </Grid>
              </Grid>

              <Card>
                <CardHeader title="错误分布" titleTypographyProps={{ variant: "subtitle1" }} />
                <CardContent>
                  {errorByPath.size === 0 ? (
                    <Typography variant="body2" align="center" sx={{ py: 3, color: "text.secondary" }}>
                      没有错误，棒！
                    </Typography>
                  ) : (
                    <Stack spacing={1}>
                      {Array.from(errorByPath.entries()).map(([path, count]) => (
                        <Stack key={path} direction="row" spacing={1.5} alignItems="center">
                          <Typography variant="body2" sx={{ fontFamily: "monospace" }}>
                            {path}
                          </Typography>
                          <Box sx={{ flex: 1 }} />
                          <Chip size="small" color="error" label={count} />
                        </Stack>
                      ))}
                    </Stack>
                  )}
                </CardContent>
              </Card>
            </>
          )}

          {view === "audit" && (
            <Card>
              <Box sx={{ height: 600 }}>
                <DataGrid
                  rows={audit}
                  columns={auditColumns}
                  getRowId={(r) => r.id}
                  density="compact"
                  pageSizeOptions={[25, 50, 100]}
                  initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
                  localeText={{ noRowsLabel: "无审计记录" }}
                  disableRowSelectionOnClick
                />
              </Box>
            </Card>
          )}

          {view === "diagnostics" && (
            <Card>
              <CardHeader title="诊断包" titleTypographyProps={{ variant: "subtitle1" }} />
              <CardContent>
                <Typography variant="body2" sx={{ color: "text.secondary" }}>
                  下载脱敏后的 activity log + debug log + settings 快照 + audit 链，适合给支持团队排障。
                </Typography>
                <Stack direction="row" spacing={1.5} sx={{ mt: 2 }} flexWrap="wrap" useFlexGap>
                  <Button startIcon={<DownloadIcon />} component="a" href="/api/admin/requests" target="_blank" rel="noreferrer">
                    下载 requests JSON
                  </Button>
                  <Button
                    variant="outlined"
                    startIcon={<DownloadIcon />}
                    component="a"
                    href="/api/admin/audit"
                    target="_blank"
                    rel="noreferrer"
                  >
                    下载 audit JSON
                  </Button>
                  <Button
                    variant="outlined"
                    startIcon={<DownloadIcon />}
                    component="a"
                    href="/api/admin/metrics/prometheus"
                    target="_blank"
                    rel="noreferrer"
                  >
                    Prometheus metrics
                  </Button>
                </Stack>
              </CardContent>
            </Card>
          )}
        </Stack>
      </Box>
    </AppShell>
  );
}

function BarChart({ title, buckets }: { title: string; buckets: number[] }) {
  const max = Math.max(...buckets, 1);
  return (
    <Card sx={{ height: "100%" }}>
      <CardContent>
        <Typography variant="caption" sx={{ color: "text.secondary" }}>
          {title}
        </Typography>
        <Box sx={{ mt: 1.5, height: 128, display: "flex", alignItems: "flex-end", gap: 0.5 }}>
          {buckets.map((v, i) => (
            <Box
              key={i}
              title={`${v}`}
              sx={{
                flex: 1,
                bgcolor: "primary.light",
                borderTopLeftRadius: 2,
                borderTopRightRadius: 2,
                height: `${(v / max) * 100}%`,
                minHeight: v > 0 ? "4px" : "1px",
              }}
            />
          ))}
        </Box>
        <Typography variant="caption" sx={{ display: "block", mt: 1, color: "text.secondary" }}>
          合计 {buckets.reduce((a, b) => a + b, 0).toLocaleString()}
        </Typography>
      </CardContent>
    </Card>
  );
}
