import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Button from "@mui/material/Button";
import Grid from "@mui/material/Grid2";
import DownloadIcon from "@mui/icons-material/Download";
import HealthAndSafetyIcon from "@mui/icons-material/HealthAndSafety";
import { AppShell } from "@/components/shell/app-shell";
import { config, configDiagnostics } from "@/lib/config";

export const dynamic = "force-dynamic";

export default function AboutPage() {
  const diag = configDiagnostics();
  return (
    <AppShell title="About" breadcrumb={["System"]}>
      <Box sx={{ maxWidth: 880, mx: "auto", p: 3 }}>
        <Stack spacing={2}>
          <Card sx={{ boxShadow: 1 }}>
            <CardContent>
              <Typography variant="h6">AIChat Relay</Typography>
              <Typography variant="body2" sx={{ mt: 1, color: "text.secondary" }}>
                企业级 Next.js 中继网关。与 macOS AIChat Relay 在路径、SSE 事件名、Gemini 请求变换上完全兼容；
                在此之上提供 Material Design 管理控制台、计费状态机、可视化策略编辑器，以及会话级对话重建。
              </Typography>
            </CardContent>
          </Card>

          <Card>
            <CardHeader title="部署信息" titleTypographyProps={{ variant: "subtitle1" }} />
            <CardContent>
              <Grid container spacing={2}>
                <InfoCell label="版本" value="1.0.0" />
                <InfoCell label="Node" value={process.version} />
                <InfoCell label="监听端口" value={String(config.port)} />
                <InfoCell label="数据目录" value={config.dataDir} />
                <InfoCell label="Billing 模式" value={diag.billingMode} />
                <InfoCell label="Gemini key" value={diag.geminiConfigured ? "已配置" : "未配置"} />
                <InfoCell label="Bearer token" value={diag.bearerConfigured ? "已配置" : "未配置"} />
                <InfoCell label="Session secret" value={diag.sessionSecretConfigured ? "已配置" : "未配置"} />
              </Grid>
            </CardContent>
          </Card>

          <Card>
            <CardHeader title="诊断与支持" titleTypographyProps={{ variant: "subtitle1" }} />
            <CardContent>
              <Stack direction="row" spacing={1.5} flexWrap="wrap" useFlexGap>
                <DownloadButton href="/api/admin/requests" label="下载 requests JSON" />
                <DownloadButton href="/api/admin/audit" label="下载 audit JSON" />
                <Button
                  variant="outlined"
                  startIcon={<HealthAndSafetyIcon />}
                  component="a"
                  href="/api/health"
                  target="_blank"
                  rel="noreferrer"
                >
                  /api/health
                </Button>
              </Stack>
            </CardContent>
          </Card>
        </Stack>
      </Box>
    </AppShell>
  );
}

function InfoCell({ label, value }: { label: string; value: string }) {
  return (
    <Grid size={{ xs: 12, md: 6 }}>
      <Typography variant="caption" sx={{ color: "text.secondary" }}>
        {label}
      </Typography>
      <Typography variant="body2" sx={{ fontFamily: "monospace", mt: 0.25, wordBreak: "break-all" }}>
        {value}
      </Typography>
    </Grid>
  );
}

function DownloadButton({ href, label }: { href: string; label: string }) {
  return (
    <Button variant="outlined" startIcon={<DownloadIcon />} component="a" href={href} download>
      {label}
    </Button>
  );
}
