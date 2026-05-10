import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
import Button from "@mui/material/Button";
import DownloadRounded from "@mui/icons-material/DownloadRounded";
import { AppShell } from "@/components/shell/app-shell";
import { configDiagnostics } from "@/lib/config";

export const dynamic = "force-dynamic";

export default function AboutPage() {
  const diag = configDiagnostics();

  const fields: Array<{ label: string; value: string | React.ReactNode }> = [
    { label: "Node 版本", value: process.version },
    { label: "进程端口", value: String(diag.port) },
    { label: "数据目录", value: diag.dataDir },
    { label: "计费模式", value: diag.billingMode },
    {
      label: "Gemini API Key",
      value: diag.geminiConfigured ? (
        <Chip size="small" label="已配置" color="success" />
      ) : (
        <Chip size="small" label="未配置" color="error" />
      ),
    },
    {
      label: "Bearer Token",
      value: diag.bearerConfigured ? (
        <Chip size="small" label="已配置" color="success" />
      ) : (
        <Chip size="small" label="未配置" color="error" />
      ),
    },
    {
      label: "Session Secret",
      value: diag.sessionSecretConfigured ? (
        <Chip size="small" label="已配置" color="success" />
      ) : (
        <Chip size="small" label="未配置" color="error" />
      ),
    },
    {
      label: "管理员",
      value: diag.adminConfigured ? (
        <Chip size="small" label="已配置" color="success" />
      ) : (
        <Chip size="small" label="未配置" color="error" />
      ),
    },
  ];

  return (
    <AppShell
      title="关于"
      breadcrumb={[{ label: "AIChat Relay", href: "/dashboard" }, { label: "关于" }]}
    >
      <Box sx={{ maxWidth: 880, mx: "auto" }}>
        <Stack spacing={3}>
          <Card>
            <CardContent>
              <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
                AIChat Relay
              </Typography>
              <Typography variant="body2" color="text.secondary">
                AIChat 的中继网关：托管 Gemini API Key、按 Bearer Token 网闸、
                按 credits 计量、SSE 转发与对话还原。Wire-compatible 于 macOS AIChat Relay。
              </Typography>
            </CardContent>
          </Card>

          <Card>
            <CardHeader title="部署信息" />
            <CardContent>
              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr" },
                  rowGap: 1.5,
                  columnGap: 3,
                }}
              >
                {fields.map((f) => (
                  <Stack key={f.label} direction="row" justifyContent="space-between" alignItems="center">
                    <Typography variant="body2" color="text.secondary">
                      {f.label}
                    </Typography>
                    {typeof f.value === "string" ? (
                      <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
                        {f.value}
                      </Typography>
                    ) : (
                      f.value
                    )}
                  </Stack>
                ))}
              </Box>
            </CardContent>
          </Card>

          <Card>
            <CardHeader title="诊断下载" />
            <CardContent>
              <Stack direction="row" spacing={1.5} flexWrap="wrap" sx={{ gap: 1.5 }}>
                <Button
                  startIcon={<DownloadRounded />}
                  variant="outlined"
                  component="a"
                  href="/api/admin/requests"
                  download="relay-requests.json"
                >
                  请求日志
                </Button>
                <Button
                  startIcon={<DownloadRounded />}
                  variant="outlined"
                  component="a"
                  href="/api/admin/audit"
                  download="relay-audit.json"
                >
                  审计日志
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
            </CardContent>
          </Card>
        </Stack>
      </Box>
    </AppShell>
  );
}
