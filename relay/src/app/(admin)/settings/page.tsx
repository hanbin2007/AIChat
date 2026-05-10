"use client";
import * as React from "react";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import TextField from "@mui/material/TextField";
import Button from "@mui/material/Button";
import Switch from "@mui/material/Switch";
import FormControlLabel from "@mui/material/FormControlLabel";
import FormGroup from "@mui/material/FormGroup";
import Slider from "@mui/material/Slider";
import ToggleButton from "@mui/material/ToggleButton";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import Chip from "@mui/material/Chip";
import Alert from "@mui/material/Alert";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import Autocomplete from "@mui/material/Autocomplete";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import Paper from "@mui/material/Paper";
import AddIcon from "@mui/icons-material/Add";
import { AppShell } from "@/components/shell/app-shell";
import { useSnackbar } from "@/components/snackbar-provider";
import type { AdminToken, SettingsSnapshot } from "@/lib/store/settings-store";

export default function SettingsPage() {
  const snack = useSnackbar();
  const [, setSnapshot] = React.useState<SettingsSnapshot | null>(null);
  const [draft, setDraft] = React.useState<SettingsSnapshot | null>(null);
  const [issueDialog, setIssueDialog] = React.useState(false);

  const refresh = React.useCallback(async () => {
    const res = await fetch("/api/admin/settings");
    const data = await res.json();
    setSnapshot(data);
    setDraft(data);
  }, []);

  React.useEffect(() => {
    refresh();
  }, [refresh]);

  async function save(patch: Partial<SettingsSnapshot>) {
    await fetch("/api/admin/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    snack.push({ message: "已保存" });
    refresh();
  }

  if (!draft) {
    return (
      <AppShell title="Settings">
        <Box sx={{ p: 3, color: "text.secondary" }}>加载中…</Box>
      </AppShell>
    );
  }

  return (
    <AppShell title="Settings" breadcrumb={["System"]}>
      <Box sx={{ maxWidth: 1080, mx: "auto", p: 3, pb: 12 }}>
        <Stack spacing={3}>
          <Alert severity="info">标红字段需要重启 relay 才会在监听器上生效。</Alert>

          <Section title="① Gateway" description="监听地址、CORS、请求体大小">
            <FormGroup>
              <FormControlLabel
                control={
                  <Switch
                    checked={draft.gateway.allowLanClients}
                    onChange={() =>
                      setDraft({
                        ...draft,
                        gateway: { ...draft.gateway, allowLanClients: !draft.gateway.allowLanClients },
                      })
                    }
                  />
                }
                label="允许 LAN 客户端"
              />
              <Typography variant="caption" sx={{ color: "text.secondary", ml: 6, mt: -0.5 }}>
                关闭后只接受 127.0.0.1 请求
              </Typography>
            </FormGroup>
            <SliderField
              label="请求体上限 (MB)"
              value={draft.gateway.requestBodyLimitMB}
              min={1}
              max={64}
              valueLabel={`${draft.gateway.requestBodyLimitMB} MB`}
              onChange={(v) =>
                setDraft({ ...draft, gateway: { ...draft.gateway, requestBodyLimitMB: v } })
              }
            />
            <Autocomplete
              multiple
              freeSolo
              options={[]}
              value={draft.gateway.corsOrigins}
              onChange={(_, v) =>
                setDraft({ ...draft, gateway: { ...draft.gateway, corsOrigins: v } })
              }
              renderTags={(value, getTagProps) =>
                value.map((option, index) => {
                  const { key, ...chipProps } = getTagProps({ index });
                  return <Chip key={key} {...chipProps} label={option} size="small" />;
                })
              }
              renderInput={(params) => (
                <TextField {...params} label="CORS origins" placeholder="https://example.com" />
              )}
            />
            <SaveRow onSave={() => save({ gateway: draft.gateway })}>保存 Gateway</SaveRow>
          </Section>

          <Section title="② Upstream · Gemini" description="超时、重试、健康检查">
            <SliderField
              label="Upstream timeout"
              value={draft.upstream.timeoutMs / 1000}
              min={5}
              max={300}
              valueLabel={`${draft.upstream.timeoutMs / 1000}s`}
              onChange={(v) =>
                setDraft({ ...draft, upstream: { ...draft.upstream, timeoutMs: v * 1000 } })
              }
            />
            <SliderField
              label="重试次数"
              value={draft.upstream.retries}
              min={0}
              max={5}
              valueLabel={String(draft.upstream.retries)}
              onChange={(v) => setDraft({ ...draft, upstream: { ...draft.upstream, retries: v } })}
            />
            <Box>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                Retry 模式
              </Typography>
              <Box sx={{ mt: 0.5 }}>
                <ToggleButtonGroup
                  size="small"
                  exclusive
                  value={draft.upstream.retryMode}
                  onChange={(_, v) =>
                    v && setDraft({ ...draft, upstream: { ...draft.upstream, retryMode: v } })
                  }
                >
                  <ToggleButton value="none">None</ToggleButton>
                  <ToggleButton value="linear">Linear</ToggleButton>
                  <ToggleButton value="exponential">Exponential</ToggleButton>
                </ToggleButtonGroup>
              </Box>
            </Box>
            <SliderField
              label="健康检查间隔"
              value={draft.upstream.healthProbeIntervalMs / 1000}
              min={0}
              max={600}
              valueLabel={`${draft.upstream.healthProbeIntervalMs / 1000}s`}
              onChange={(v) =>
                setDraft({
                  ...draft,
                  upstream: { ...draft.upstream, healthProbeIntervalMs: v * 1000 },
                })
              }
            />
            <SaveRow onSave={() => save({ upstream: draft.upstream })}>保存 Upstream</SaveRow>
          </Section>

          <Section title="③ Auth & Tokens" description="Bearer 签发、吊销、限流">
            <Box sx={{ display: "flex", alignItems: "center", justifyContent: "space-between", mb: 1 }}>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                已签发 token
              </Typography>
              <Button startIcon={<AddIcon />} size="small" onClick={() => setIssueDialog(true)}>
                签发新 token
              </Button>
            </Box>
            <TokenTable
              tokens={draft.adminTokens}
              onRevoke={async (id) => {
                await fetch(`/api/admin/tokens?id=${id}`, { method: "DELETE" });
                refresh();
              }}
            />
          </Section>

          <Section title="④ Rate limits" description="全局 / 单 token / 单 IP 节流">
            <SliderField
              label="Global RPM"
              value={draft.rateLimits.globalRpm}
              min={0}
              max={10000}
              step={100}
              valueLabel={draft.rateLimits.globalRpm.toLocaleString()}
              onChange={(v) =>
                setDraft({ ...draft, rateLimits: { ...draft.rateLimits, globalRpm: v } })
              }
            />
            <SliderField
              label="Per-token RPM"
              value={draft.rateLimits.perTokenRpm}
              min={0}
              max={3000}
              step={10}
              valueLabel={draft.rateLimits.perTokenRpm.toLocaleString()}
              onChange={(v) =>
                setDraft({ ...draft, rateLimits: { ...draft.rateLimits, perTokenRpm: v } })
              }
            />
            <SliderField
              label="最大并发流"
              value={draft.rateLimits.concurrentStreams}
              min={1}
              max={512}
              valueLabel={String(draft.rateLimits.concurrentStreams)}
              onChange={(v) =>
                setDraft({ ...draft, rateLimits: { ...draft.rateLimits, concurrentStreams: v } })
              }
            />
            <SliderField
              label="Per-IP RPM"
              value={draft.rateLimits.perIpRpm}
              min={0}
              max={5000}
              step={50}
              valueLabel={draft.rateLimits.perIpRpm.toLocaleString()}
              onChange={(v) =>
                setDraft({ ...draft, rateLimits: { ...draft.rateLimits, perIpRpm: v } })
              }
            />
            <SaveRow onSave={() => save({ rateLimits: draft.rateLimits })}>保存限流</SaveRow>
          </Section>

          <Section title="⑤ Billing mode" description="计费三种来源的开关">
            <FormGroup>
              <FormControlLabel
                control={
                  <Switch
                    checked={draft.billing.trialEnabled}
                    onChange={() =>
                      setDraft({
                        ...draft,
                        billing: { ...draft.billing, trialEnabled: !draft.billing.trialEnabled },
                      })
                    }
                  />
                }
                label="试用账户"
              />
              <FormControlLabel
                control={
                  <Switch
                    checked={draft.billing.subscriptionEnabled}
                    onChange={() =>
                      setDraft({
                        ...draft,
                        billing: {
                          ...draft.billing,
                          subscriptionEnabled: !draft.billing.subscriptionEnabled,
                        },
                      })
                    }
                  />
                }
                label="订阅 (StoreKit)"
              />
              <FormControlLabel
                control={
                  <Switch
                    checked={draft.billing.offlineEnabled}
                    onChange={() =>
                      setDraft({
                        ...draft,
                        billing: { ...draft.billing, offlineEnabled: !draft.billing.offlineEnabled },
                      })
                    }
                  />
                }
                label="离线激活码"
              />
            </FormGroup>
            <Alert severity="info">
              StoreKit 验签模式：<Chip size="small" label={draft.billing.mode} sx={{ mx: 0.5 }} /> ·
              strict 模式预留到 v1.2。
            </Alert>
            <SaveRow onSave={() => save({ billing: draft.billing })}>保存 Billing</SaveRow>
          </Section>

          <Section title="⑥ Observability" description="日志、脱敏、Prometheus">
            <SliderField
              label="Activity log 大小"
              value={draft.observability.activityLogSize}
              min={100}
              max={5000}
              step={100}
              valueLabel={draft.observability.activityLogSize.toLocaleString()}
              onChange={(v) =>
                setDraft({ ...draft, observability: { ...draft.observability, activityLogSize: v } })
              }
            />
            <SliderField
              label="Debug log 大小"
              value={draft.observability.debugLogSize}
              min={0}
              max={2000}
              step={50}
              valueLabel={draft.observability.debugLogSize.toLocaleString()}
              onChange={(v) =>
                setDraft({ ...draft, observability: { ...draft.observability, debugLogSize: v } })
              }
            />
            <FormGroup>
              <FormControlLabel
                control={
                  <Switch
                    checked={draft.observability.debugLoggingEnabled}
                    onChange={() =>
                      setDraft({
                        ...draft,
                        observability: {
                          ...draft.observability,
                          debugLoggingEnabled: !draft.observability.debugLoggingEnabled,
                        },
                      })
                    }
                  />
                }
                label="Debug logging"
              />
              <Typography variant="caption" sx={{ color: "text.secondary", ml: 6, mt: -0.5 }}>
                捕获客户端/上游的 JSON payload（敏感）
              </Typography>
            </FormGroup>
            <SliderField
              label="日志采样率"
              value={draft.observability.logSamplingRate * 100}
              min={1}
              max={100}
              valueLabel={`${(draft.observability.logSamplingRate * 100).toFixed(0)}%`}
              onChange={(v) =>
                setDraft({
                  ...draft,
                  observability: { ...draft.observability, logSamplingRate: v / 100 },
                })
              }
            />
            <FormGroup>
              <FormControlLabel
                control={
                  <Switch
                    checked={draft.observability.prometheusEnabled}
                    onChange={() =>
                      setDraft({
                        ...draft,
                        observability: {
                          ...draft.observability,
                          prometheusEnabled: !draft.observability.prometheusEnabled,
                        },
                      })
                    }
                  />
                }
                label="启用 Prometheus /metrics"
              />
            </FormGroup>
            <SaveRow onSave={() => save({ observability: draft.observability })}>
              保存 Observability
            </SaveRow>
          </Section>

          <Section title="⑦ Localization" description="默认语言与时区">
            <Box>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                默认语言
              </Typography>
              <Box sx={{ mt: 0.5 }}>
                <ToggleButtonGroup
                  size="small"
                  exclusive
                  value={draft.localization.defaultLocale}
                  onChange={(_, v) =>
                    v &&
                    setDraft({ ...draft, localization: { ...draft.localization, defaultLocale: v } })
                  }
                >
                  <ToggleButton value="zh-Hans">简体中文</ToggleButton>
                  <ToggleButton value="en">English</ToggleButton>
                </ToggleButtonGroup>
              </Box>
            </Box>
            <TextField
              label="时区"
              value={draft.localization.timezone}
              onChange={(e) =>
                setDraft({
                  ...draft,
                  localization: { ...draft.localization, timezone: e.target.value },
                })
              }
            />
            <SaveRow onSave={() => save({ localization: draft.localization })}>
              保存 Localization
            </SaveRow>
          </Section>
        </Stack>
      </Box>

      {issueDialog && (
        <TokenIssueDialog
          onClose={() => setIssueDialog(false)}
          onDone={() => {
            setIssueDialog(false);
            refresh();
          }}
        />
      )}
    </AppShell>
  );
}

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <Card sx={{ bgcolor: "action.hover" }}>
      <CardHeader
        title={title}
        subheader={description}
        titleTypographyProps={{ variant: "subtitle1" }}
        subheaderTypographyProps={{ variant: "caption" }}
      />
      <CardContent>
        <Stack spacing={2}>{children}</Stack>
      </CardContent>
    </Card>
  );
}

function SaveRow({ onSave, children }: { onSave: () => void; children: React.ReactNode }) {
  return (
    <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
      <Button onClick={onSave}>{children}</Button>
    </Box>
  );
}

function SliderField({
  label,
  value,
  min,
  max,
  step,
  valueLabel,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  valueLabel?: string;
  onChange: (v: number) => void;
}) {
  return (
    <Box>
      <Stack direction="row" spacing={1} alignItems="baseline" justifyContent="space-between">
        <Typography variant="body2">{label}</Typography>
        {valueLabel && (
          <Typography variant="caption" sx={{ color: "text.secondary", fontFamily: "monospace" }}>
            {valueLabel}
          </Typography>
        )}
      </Stack>
      <Slider
        size="small"
        value={value}
        min={min}
        max={max}
        step={step ?? 1}
        onChange={(_, v) => onChange(v as number)}
      />
    </Box>
  );
}

function TokenTable({ tokens, onRevoke }: { tokens: AdminToken[]; onRevoke: (id: string) => void }) {
  return (
    <TableContainer component={Paper} variant="outlined">
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Label</TableCell>
            <TableCell>Scope</TableCell>
            <TableCell>Prefix</TableCell>
            <TableCell>创建</TableCell>
            <TableCell>最近使用</TableCell>
            <TableCell />
          </TableRow>
        </TableHead>
        <TableBody>
          {tokens.length === 0 && (
            <TableRow>
              <TableCell colSpan={6} align="center" sx={{ color: "text.secondary", py: 3 }}>
                还没有签发 token
              </TableCell>
            </TableRow>
          )}
          {tokens.map((t) => (
            <TableRow key={t.id} hover>
              <TableCell>{t.label}</TableCell>
              <TableCell>
                <Chip size="small" color={t.scope === "admin" ? "warning" : "info"} label={t.scope} />
              </TableCell>
              <TableCell sx={{ fontFamily: "monospace" }}>{t.prefix}</TableCell>
              <TableCell>{new Date(t.createdAt).toLocaleDateString()}</TableCell>
              <TableCell>{t.lastUsedAt ? new Date(t.lastUsedAt).toLocaleString() : "—"}</TableCell>
              <TableCell align="right">
                {t.revoked ? (
                  <Chip size="small" color="error" label="revoked" />
                ) : (
                  <Button variant="text" size="small" onClick={() => onRevoke(t.id)}>
                    吊销
                  </Button>
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
}

function TokenIssueDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const snack = useSnackbar();
  const [label, setLabel] = React.useState("");
  const [scope, setScope] = React.useState<"admin" | "client">("client");
  const [rpm, setRpm] = React.useState(300);
  const [issued, setIssued] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState(false);

  async function submit() {
    setBusy(true);
    const res = await fetch("/api/admin/tokens", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ label, scope, rpmLimit: rpm }),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) {
      snack.push({ message: data.message ?? "失败" });
      return;
    }
    setIssued(data.value as string);
  }

  return (
    <Dialog open onClose={issued ? onDone : onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{issued ? "Token 已签发 — 仅显示一次" : "签发 bearer token"}</DialogTitle>
      <DialogContent>
        {issued ? (
          <Stack spacing={2}>
            <Alert severity="warning">关闭后无法再次显示，请立即复制保存。</Alert>
            <Box
              component="pre"
              sx={{
                wordBreak: "break-all",
                whiteSpace: "pre-wrap",
                bgcolor: "action.hover",
                borderRadius: 2,
                p: 1.5,
                fontFamily: "monospace",
                fontSize: "0.875rem",
              }}
            >
              {issued}
            </Box>
          </Stack>
        ) : (
          <Stack spacing={2} sx={{ pt: 1 }}>
            <TextField label="标签" value={label} onChange={(e) => setLabel(e.target.value)} />
            <Box>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                Scope
              </Typography>
              <Stack direction="row" spacing={1} sx={{ mt: 0.5 }}>
                <Chip
                  label="Admin"
                  color={scope === "admin" ? "primary" : "default"}
                  variant={scope === "admin" ? "filled" : "outlined"}
                  onClick={() => setScope("admin")}
                />
                <Chip
                  label="Client"
                  color={scope === "client" ? "primary" : "default"}
                  variant={scope === "client" ? "filled" : "outlined"}
                  onClick={() => setScope("client")}
                />
              </Stack>
            </Box>
            <SliderField
              label="每分钟请求上限"
              value={rpm}
              min={0}
              max={3000}
              step={10}
              valueLabel={`${rpm}/min`}
              onChange={setRpm}
            />
          </Stack>
        )}
      </DialogContent>
      <DialogActions>
        {issued ? (
          <Button onClick={onDone}>完成</Button>
        ) : (
          <>
            <Button variant="text" onClick={onClose}>
              取消
            </Button>
            <Button onClick={submit} disabled={!label || busy}>
              {busy ? "签发中…" : "签发"}
            </Button>
          </>
        )}
      </DialogActions>
    </Dialog>
  );
}
