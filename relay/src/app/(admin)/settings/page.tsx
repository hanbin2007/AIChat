"use client";

import { useCallback, useEffect, useState } from "react";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Switch from "@mui/material/Switch";
import FormControlLabel from "@mui/material/FormControlLabel";
import Slider from "@mui/material/Slider";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import TextField from "@mui/material/TextField";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import ToggleButton from "@mui/material/ToggleButton";
import Autocomplete from "@mui/material/Autocomplete";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import Chip from "@mui/material/Chip";
import Alert from "@mui/material/Alert";
import AlertTitle from "@mui/material/AlertTitle";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import AddRounded from "@mui/icons-material/AddRounded";
import DeleteRounded from "@mui/icons-material/DeleteRounded";
import RefreshRounded from "@mui/icons-material/RefreshRounded";
import { AppShell } from "@/components/shell/app-shell";
import { useSnackbar } from "@/components/snackbar-provider";
import type { SettingsSnapshot, AdminToken } from "@/lib/store/settings-store";

export default function SettingsPage() {
  const snackbar = useSnackbar();
  const [snap, setSnap] = useState<SettingsSnapshot | null>(null);
  const [tokenDialog, setTokenDialog] = useState(false);
  const [tokenForm, setTokenForm] = useState({
    label: "",
    scope: "client" as "admin" | "client",
    rpmLimit: 60,
  });
  const [issuedToken, setIssuedToken] = useState<AdminToken | null>(null);

  const load = useCallback(async () => {
    const res = await fetch("/api/admin/settings");
    if (!res.ok) {
      snackbar.push({ message: "拉取设置失败", severity: "error" });
      return;
    }
    const data = (await res.json()) as SettingsSnapshot;
    setSnap(data);
  }, [snackbar]);

  useEffect(() => {
    void load();
  }, [load]);

  const patch = async (slice: Partial<SettingsSnapshot>) => {
    const res = await fetch("/api/admin/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(slice),
    });
    if (res.ok) {
      snackbar.push({ message: "已保存", severity: "success" });
      void load();
    } else {
      snackbar.push({ message: "保存失败", severity: "error" });
    }
  };

  const issueToken = async () => {
    const res = await fetch("/api/admin/tokens", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(tokenForm),
    });
    if (res.ok) {
      const token = (await res.json()) as AdminToken;
      setIssuedToken(token);
      setTokenDialog(false);
      void load();
    } else {
      snackbar.push({ message: "签发失败", severity: "error" });
    }
  };

  const revokeToken = async (id: string) => {
    if (!confirm("确定要撤销此 token 吗？")) return;
    const res = await fetch(`/api/admin/tokens?id=${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
    if (res.ok) {
      snackbar.push({ message: "已撤销", severity: "success" });
      void load();
    } else {
      snackbar.push({ message: "撤销失败", severity: "error" });
    }
  };

  if (!snap) {
    return (
      <AppShell title="设置">
        <Typography color="text.secondary">加载中…</Typography>
      </AppShell>
    );
  }

  return (
    <AppShell
      title="设置"
      breadcrumb={[{ label: "AIChat Relay", href: "/dashboard" }, { label: "设置" }]}
      actions={
        <Tooltip title="刷新">
          <IconButton aria-label="刷新" onClick={() => void load()}>
            <RefreshRounded />
          </IconButton>
        </Tooltip>
      }
    >
      <Box sx={{ maxWidth: 1080, mx: "auto" }}>
        <Stack spacing={2.5}>
          <Section
            title="网关 (Gateway)"
            onSave={() => void patch({ gateway: snap.gateway })}
          >
            <FormControlLabel
              control={
                <Switch
                  checked={snap.gateway.allowLanClients}
                  onChange={(e) =>
                    setSnap({
                      ...snap,
                      gateway: { ...snap.gateway, allowLanClients: e.target.checked },
                    })
                  }
                />
              }
              label="允许 LAN 客户端"
            />
            <SliderField
              label={`请求体上限 · ${snap.gateway.requestBodyLimitMB} MB`}
              value={snap.gateway.requestBodyLimitMB}
              min={1}
              max={64}
              step={1}
              onChange={(v) =>
                setSnap({
                  ...snap,
                  gateway: { ...snap.gateway, requestBodyLimitMB: v },
                })
              }
            />
            <Autocomplete
              multiple
              freeSolo
              options={[]}
              value={snap.gateway.corsOrigins}
              onChange={(_e, v) =>
                setSnap({
                  ...snap,
                  gateway: { ...snap.gateway, corsOrigins: v as string[] },
                })
              }
              renderInput={(params) => (
                <TextField {...params} label="CORS 允许来源" size="small" />
              )}
            />
          </Section>

          <Section
            title="上游 · Gemini"
            onSave={() => void patch({ upstream: snap.upstream })}
          >
            <SliderField
              label={`超时 · ${(snap.upstream.timeoutMs / 1000).toFixed(0)}s`}
              value={snap.upstream.timeoutMs / 1000}
              min={5}
              max={120}
              step={1}
              onChange={(v) =>
                setSnap({ ...snap, upstream: { ...snap.upstream, timeoutMs: v * 1000 } })
              }
            />
            <SliderField
              label={`重试次数 · ${snap.upstream.retries}`}
              value={snap.upstream.retries}
              min={0}
              max={5}
              step={1}
              onChange={(v) => setSnap({ ...snap, upstream: { ...snap.upstream, retries: v } })}
            />
            <Box>
              <Typography variant="caption" color="text.secondary">
                重试模式
              </Typography>
              <ToggleButtonGroup
                exclusive
                size="small"
                value={snap.upstream.retryMode}
                onChange={(_e, v) => {
                  if (v)
                    setSnap({
                      ...snap,
                      upstream: { ...snap.upstream, retryMode: v },
                    });
                }}
                sx={{ display: "block", mt: 0.5 }}
              >
                <ToggleButton value="none">none</ToggleButton>
                <ToggleButton value="linear">linear</ToggleButton>
                <ToggleButton value="exponential">exponential</ToggleButton>
              </ToggleButtonGroup>
            </Box>
            <SliderField
              label={`健康探测间隔 · ${(snap.upstream.healthProbeIntervalMs / 1000).toFixed(0)}s`}
              value={snap.upstream.healthProbeIntervalMs / 1000}
              min={5}
              max={300}
              step={5}
              onChange={(v) =>
                setSnap({
                  ...snap,
                  upstream: { ...snap.upstream, healthProbeIntervalMs: v * 1000 },
                })
              }
            />
          </Section>

          <Section title="认证 & Tokens" onSave={null}>
            <Stack direction="row" justifyContent="space-between" alignItems="center">
              <Typography variant="body2" color="text.secondary">
                {snap.adminTokens.length} 个 token
              </Typography>
              <Button
                size="small"
                variant="contained"
                startIcon={<AddRounded />}
                onClick={() => setTokenDialog(true)}
              >
                签发新 token
              </Button>
            </Stack>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>名称</TableCell>
                  <TableCell>Scope</TableCell>
                  <TableCell>前缀</TableCell>
                  <TableCell align="right">RPM</TableCell>
                  <TableCell>状态</TableCell>
                  <TableCell>签发于</TableCell>
                  <TableCell> </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {snap.adminTokens.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={7}>
                      <Typography
                        variant="body2"
                        color="text.secondary"
                        sx={{ textAlign: "center", py: 2 }}
                      >
                        无 token
                      </Typography>
                    </TableCell>
                  </TableRow>
                ) : (
                  snap.adminTokens.map((t) => (
                    <TableRow key={t.id}>
                      <TableCell>{t.label}</TableCell>
                      <TableCell>
                        <Chip size="small" label={t.scope} />
                      </TableCell>
                      <TableCell sx={{ fontFamily: "var(--font-mono)" }}>{t.prefix}…</TableCell>
                      <TableCell align="right">{t.rpmLimit ?? "—"}</TableCell>
                      <TableCell>
                        {t.revoked ? (
                          <Chip size="small" label="已撤销" color="error" />
                        ) : (
                          <Chip size="small" label="活跃" color="success" />
                        )}
                      </TableCell>
                      <TableCell>{new Date(t.createdAt).toLocaleString("zh-Hans")}</TableCell>
                      <TableCell>
                        {!t.revoked ? (
                          <IconButton
                            aria-label="撤销"
                            size="small"
                            onClick={() => void revokeToken(t.id)}
                          >
                            <DeleteRounded fontSize="small" />
                          </IconButton>
                        ) : null}
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </Section>

          <Section
            title="速率限制"
            onSave={() => void patch({ rateLimits: snap.rateLimits })}
          >
            <SliderField
              label={`全局 RPM · ${snap.rateLimits.globalRpm}`}
              value={snap.rateLimits.globalRpm}
              min={10}
              max={5000}
              step={10}
              onChange={(v) =>
                setSnap({ ...snap, rateLimits: { ...snap.rateLimits, globalRpm: v } })
              }
            />
            <SliderField
              label={`单 token RPM · ${snap.rateLimits.perTokenRpm}`}
              value={snap.rateLimits.perTokenRpm}
              min={10}
              max={1000}
              step={10}
              onChange={(v) =>
                setSnap({ ...snap, rateLimits: { ...snap.rateLimits, perTokenRpm: v } })
              }
            />
            <SliderField
              label={`并发流上限 · ${snap.rateLimits.concurrentStreams}`}
              value={snap.rateLimits.concurrentStreams}
              min={1}
              max={200}
              step={1}
              onChange={(v) =>
                setSnap({ ...snap, rateLimits: { ...snap.rateLimits, concurrentStreams: v } })
              }
            />
            <SliderField
              label={`单 IP RPM · ${snap.rateLimits.perIpRpm}`}
              value={snap.rateLimits.perIpRpm}
              min={5}
              max={500}
              step={5}
              onChange={(v) =>
                setSnap({ ...snap, rateLimits: { ...snap.rateLimits, perIpRpm: v } })
              }
            />
          </Section>

          <Section title="计费模式" onSave={() => void patch({ billing: snap.billing })}>
            <FormControlLabel
              control={
                <Switch
                  checked={snap.billing.trialEnabled}
                  onChange={(e) =>
                    setSnap({
                      ...snap,
                      billing: { ...snap.billing, trialEnabled: e.target.checked },
                    })
                  }
                />
              }
              label="启用试用"
            />
            <FormControlLabel
              control={
                <Switch
                  checked={snap.billing.subscriptionEnabled}
                  onChange={(e) =>
                    setSnap({
                      ...snap,
                      billing: { ...snap.billing, subscriptionEnabled: e.target.checked },
                    })
                  }
                />
              }
              label="启用订阅"
            />
            <FormControlLabel
              control={
                <Switch
                  checked={snap.billing.offlineEnabled}
                  onChange={(e) =>
                    setSnap({
                      ...snap,
                      billing: { ...snap.billing, offlineEnabled: e.target.checked },
                    })
                  }
                />
              }
              label="启用离线激活"
            />
            <Alert severity="info">
              当前 StoreKit 验签模式：
              <Box component="code" sx={{ fontFamily: "var(--font-mono)", ml: 1 }}>
                {snap.billing.mode}
              </Box>
            </Alert>
          </Section>

          <Section
            title="可观测性"
            onSave={() => void patch({ observability: snap.observability })}
          >
            <SliderField
              label={`活动日志容量 · ${snap.observability.activityLogSize}`}
              value={snap.observability.activityLogSize}
              min={100}
              max={5000}
              step={100}
              onChange={(v) =>
                setSnap({
                  ...snap,
                  observability: { ...snap.observability, activityLogSize: v },
                })
              }
            />
            <SliderField
              label={`调试日志容量 · ${snap.observability.debugLogSize}`}
              value={snap.observability.debugLogSize}
              min={100}
              max={5000}
              step={100}
              onChange={(v) =>
                setSnap({
                  ...snap,
                  observability: { ...snap.observability, debugLogSize: v },
                })
              }
            />
            <FormControlLabel
              control={
                <Switch
                  checked={snap.observability.debugLoggingEnabled}
                  onChange={(e) =>
                    setSnap({
                      ...snap,
                      observability: {
                        ...snap.observability,
                        debugLoggingEnabled: e.target.checked,
                      },
                    })
                  }
                />
              }
              label="开启调试日志"
            />
            <FormControlLabel
              control={
                <Switch
                  checked={snap.observability.prometheusEnabled}
                  onChange={(e) =>
                    setSnap({
                      ...snap,
                      observability: {
                        ...snap.observability,
                        prometheusEnabled: e.target.checked,
                      },
                    })
                  }
                />
              }
              label="开放 Prometheus 端点"
            />
          </Section>

          <Section
            title="本地化"
            onSave={() => void patch({ localization: snap.localization })}
          >
            <Box>
              <Typography variant="caption" color="text.secondary">
                默认语言
              </Typography>
              <ToggleButtonGroup
                exclusive
                size="small"
                value={snap.localization.defaultLocale}
                onChange={(_e, v) => {
                  if (v)
                    setSnap({
                      ...snap,
                      localization: { ...snap.localization, defaultLocale: v },
                    });
                }}
                sx={{ display: "block", mt: 0.5 }}
              >
                <ToggleButton value="zh-Hans">zh-Hans</ToggleButton>
                <ToggleButton value="en">en</ToggleButton>
              </ToggleButtonGroup>
            </Box>
            <TextField
              label="时区"
              size="small"
              value={snap.localization.timezone}
              onChange={(e) =>
                setSnap({
                  ...snap,
                  localization: { ...snap.localization, timezone: e.target.value },
                })
              }
            />
          </Section>
        </Stack>
      </Box>

      <Dialog open={tokenDialog} onClose={() => setTokenDialog(false)} maxWidth="xs" fullWidth>
        <DialogTitle>签发新 token</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField
              label="名称"
              value={tokenForm.label}
              onChange={(e) => setTokenForm({ ...tokenForm, label: e.target.value })}
            />
            <ToggleButtonGroup
              exclusive
              value={tokenForm.scope}
              onChange={(_e, v) => {
                if (v) setTokenForm({ ...tokenForm, scope: v });
              }}
            >
              <ToggleButton value="admin">admin</ToggleButton>
              <ToggleButton value="client">client</ToggleButton>
            </ToggleButtonGroup>
            <Box>
              <Typography variant="caption" color="text.secondary">
                RPM 限制 · {tokenForm.rpmLimit}
              </Typography>
              <Slider
                value={tokenForm.rpmLimit}
                min={1}
                max={1000}
                step={5}
                onChange={(_e, v) =>
                  setTokenForm({ ...tokenForm, rpmLimit: typeof v === "number" ? v : v[0] })
                }
              />
            </Box>
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setTokenDialog(false)}>取消</Button>
          <Button variant="contained" onClick={issueToken} disabled={!tokenForm.label}>
            签发
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={Boolean(issuedToken)}
        onClose={() => setIssuedToken(null)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>新 token 已签发</DialogTitle>
        <DialogContent>
          {issuedToken ? (
            <Stack spacing={2}>
              <Alert severity="warning">
                <AlertTitle>请立即复制保存</AlertTitle>
                此 token 仅在本次显示，离开后无法再次查看
              </Alert>
              <Box
                component="pre"
                sx={{
                  fontFamily: "var(--font-mono)",
                  fontSize: "0.8125rem",
                  bgcolor: "action.hover",
                  p: 2,
                  borderRadius: 1,
                  m: 0,
                  overflowX: "auto",
                  wordBreak: "break-all",
                  whiteSpace: "pre-wrap",
                }}
              >
                {issuedToken.value}
              </Box>
            </Stack>
          ) : null}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setIssuedToken(null)}>知道了</Button>
        </DialogActions>
      </Dialog>
    </AppShell>
  );
}

function Section({
  title,
  children,
  onSave,
}: {
  title: string;
  children: React.ReactNode;
  onSave: (() => void) | null;
}) {
  return (
    <Card sx={{ bgcolor: "action.hover" }}>
      <CardHeader
        title={
          <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
            {title}
          </Typography>
        }
        action={
          onSave ? (
            <Button size="small" variant="contained" onClick={onSave}>
              保存
            </Button>
          ) : null
        }
      />
      <CardContent>
        <Stack spacing={2}>{children}</Stack>
      </CardContent>
    </Card>
  );
}

function SliderField({
  label,
  value,
  min,
  max,
  step,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
}) {
  return (
    <Box>
      <Typography variant="caption" color="text.secondary">
        {label}
      </Typography>
      <Slider
        value={value}
        min={min}
        max={max}
        step={step}
        onChange={(_e, v) => onChange(typeof v === "number" ? v : v[0])}
        size="small"
      />
    </Box>
  );
}
