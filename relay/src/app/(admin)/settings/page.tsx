"use client";
import * as React from "react";
import { AdminShell } from "@/components/admin-shell";
import { Banner, Card, CardContent, CardHeader, CardTitle, Chip, Switch, TextField, Slider, Segmented, Button, Icon, Badge, Dialog, useSnackbar } from "@/components/m3";
import type { AdminToken, SettingsSnapshot } from "@/lib/store/settings-store";

export default function SettingsPage() {
  const snack = useSnackbar();
  const [snapshot, setSnapshot] = React.useState<SettingsSnapshot | null>(null);
  const [draft, setDraft] = React.useState<SettingsSnapshot | null>(null);
  const [issueDialog, setIssueDialog] = React.useState(false);

  async function refresh() {
    const res = await fetch("/api/admin/settings");
    const data = await res.json();
    setSnapshot(data);
    setDraft(data);
  }
  React.useEffect(() => { refresh(); }, []);

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
      <AdminShell title="Settings">
        <div className="p-6 text-on-surface-variant">加载中…</div>
      </AdminShell>
    );
  }

  return (
    <AdminShell title="Settings" breadcrumb={["System"]}>
      <div className="mx-auto max-w-5xl space-y-6 p-6 pb-24">
        <Banner tone="info">
          标红字段需要重启 relay 才会在监听器上生效。
        </Banner>

        <Section title="① Gateway" description="监听地址、CORS、请求体大小">
          <Switch
            label="允许 LAN 客户端"
            supporting="关闭后只接受 127.0.0.1 请求"
            checked={draft.gateway.allowLanClients}
            onChange={() => setDraft({ ...draft, gateway: { ...draft.gateway, allowLanClients: !draft.gateway.allowLanClients } })}
          />
          <Slider
            label="请求体上限 (MB)"
            value={draft.gateway.requestBodyLimitMB}
            min={1}
            max={64}
            valueLabel={`${draft.gateway.requestBodyLimitMB} MB`}
            onChange={(v) => setDraft({ ...draft, gateway: { ...draft.gateway, requestBodyLimitMB: v } })}
          />
          <ChipInput
            label="CORS origins"
            values={draft.gateway.corsOrigins}
            onChange={(v) => setDraft({ ...draft, gateway: { ...draft.gateway, corsOrigins: v } })}
            placeholder="https://example.com"
          />
          <div className="flex justify-end">
            <Button onClick={() => save({ gateway: draft.gateway })}>保存 Gateway</Button>
          </div>
        </Section>

        <Section title="② Upstream · Gemini" description="超时、重试、健康检查">
          <Slider
            label="Upstream timeout"
            value={draft.upstream.timeoutMs / 1000}
            min={5}
            max={300}
            valueLabel={`${draft.upstream.timeoutMs / 1000}s`}
            onChange={(v) => setDraft({ ...draft, upstream: { ...draft.upstream, timeoutMs: v * 1000 } })}
          />
          <Slider
            label="重试次数"
            value={draft.upstream.retries}
            min={0}
            max={5}
            valueLabel={String(draft.upstream.retries)}
            onChange={(v) => setDraft({ ...draft, upstream: { ...draft.upstream, retries: v } })}
          />
          <div>
            <div className="text-m3-label-m text-on-surface-variant">Retry 模式</div>
            <div className="mt-1">
              <Segmented
                value={draft.upstream.retryMode}
                onChange={(v) => setDraft({ ...draft, upstream: { ...draft.upstream, retryMode: v } })}
                options={[
                  { value: "none", label: "None" },
                  { value: "linear", label: "Linear" },
                  { value: "exponential", label: "Exponential" },
                ]}
              />
            </div>
          </div>
          <Slider
            label="健康检查间隔"
            value={draft.upstream.healthProbeIntervalMs / 1000}
            min={0}
            max={600}
            valueLabel={`${draft.upstream.healthProbeIntervalMs / 1000}s`}
            onChange={(v) => setDraft({ ...draft, upstream: { ...draft.upstream, healthProbeIntervalMs: v * 1000 } })}
          />
          <div className="flex justify-end">
            <Button onClick={() => save({ upstream: draft.upstream })}>保存 Upstream</Button>
          </div>
        </Section>

        <Section title="③ Auth & Tokens" description="Bearer 签发、吊销、限流">
          <div>
            <div className="mb-2 flex items-center justify-between">
              <span className="text-m3-label-m text-on-surface-variant">已签发 token</span>
              <Button icon="add" onClick={() => setIssueDialog(true)}>签发新 token</Button>
            </div>
            <TokenTable tokens={draft.adminTokens} onRevoke={async (id) => {
              await fetch(`/api/admin/tokens?id=${id}`, { method: "DELETE" });
              refresh();
            }} />
          </div>
        </Section>

        <Section title="④ Rate limits" description="全局 / 单 token / 单 IP 节流">
          <Slider
            label="Global RPM"
            value={draft.rateLimits.globalRpm}
            min={0}
            max={10000}
            step={100}
            valueLabel={draft.rateLimits.globalRpm.toLocaleString()}
            onChange={(v) => setDraft({ ...draft, rateLimits: { ...draft.rateLimits, globalRpm: v } })}
          />
          <Slider
            label="Per-token RPM"
            value={draft.rateLimits.perTokenRpm}
            min={0}
            max={3000}
            step={10}
            valueLabel={draft.rateLimits.perTokenRpm.toLocaleString()}
            onChange={(v) => setDraft({ ...draft, rateLimits: { ...draft.rateLimits, perTokenRpm: v } })}
          />
          <Slider
            label="最大并发流"
            value={draft.rateLimits.concurrentStreams}
            min={1}
            max={512}
            valueLabel={String(draft.rateLimits.concurrentStreams)}
            onChange={(v) => setDraft({ ...draft, rateLimits: { ...draft.rateLimits, concurrentStreams: v } })}
          />
          <Slider
            label="Per-IP RPM"
            value={draft.rateLimits.perIpRpm}
            min={0}
            max={5000}
            step={50}
            valueLabel={draft.rateLimits.perIpRpm.toLocaleString()}
            onChange={(v) => setDraft({ ...draft, rateLimits: { ...draft.rateLimits, perIpRpm: v } })}
          />
          <div className="flex justify-end">
            <Button onClick={() => save({ rateLimits: draft.rateLimits })}>保存限流</Button>
          </div>
        </Section>

        <Section title="⑤ Billing mode" description="计费三种来源的开关">
          <Switch
            label="试用账户"
            checked={draft.billing.trialEnabled}
            onChange={() => setDraft({ ...draft, billing: { ...draft.billing, trialEnabled: !draft.billing.trialEnabled } })}
          />
          <Switch
            label="订阅 (StoreKit)"
            checked={draft.billing.subscriptionEnabled}
            onChange={() => setDraft({ ...draft, billing: { ...draft.billing, subscriptionEnabled: !draft.billing.subscriptionEnabled } })}
          />
          <Switch
            label="离线激活码"
            checked={draft.billing.offlineEnabled}
            onChange={() => setDraft({ ...draft, billing: { ...draft.billing, offlineEnabled: !draft.billing.offlineEnabled } })}
          />
          <Banner tone="info">
            StoreKit 验签模式：<Badge>{draft.billing.mode}</Badge> · strict 模式预留到 v1.2。
          </Banner>
          <div className="flex justify-end">
            <Button onClick={() => save({ billing: draft.billing })}>保存 Billing</Button>
          </div>
        </Section>

        <Section title="⑥ Observability" description="日志、脱敏、Prometheus">
          <Slider
            label="Activity log 大小"
            value={draft.observability.activityLogSize}
            min={100}
            max={5000}
            step={100}
            valueLabel={draft.observability.activityLogSize.toLocaleString()}
            onChange={(v) => setDraft({ ...draft, observability: { ...draft.observability, activityLogSize: v } })}
          />
          <Slider
            label="Debug log 大小"
            value={draft.observability.debugLogSize}
            min={0}
            max={2000}
            step={50}
            valueLabel={draft.observability.debugLogSize.toLocaleString()}
            onChange={(v) => setDraft({ ...draft, observability: { ...draft.observability, debugLogSize: v } })}
          />
          <Switch
            label="Debug logging"
            supporting="捕获客户端/上游的 JSON payload（敏感）"
            checked={draft.observability.debugLoggingEnabled}
            onChange={() => setDraft({ ...draft, observability: { ...draft.observability, debugLoggingEnabled: !draft.observability.debugLoggingEnabled } })}
          />
          <Slider
            label="日志采样率"
            value={draft.observability.logSamplingRate * 100}
            min={1}
            max={100}
            valueLabel={`${(draft.observability.logSamplingRate * 100).toFixed(0)}%`}
            onChange={(v) => setDraft({ ...draft, observability: { ...draft.observability, logSamplingRate: v / 100 } })}
          />
          <Switch
            label="启用 Prometheus /metrics"
            checked={draft.observability.prometheusEnabled}
            onChange={() => setDraft({ ...draft, observability: { ...draft.observability, prometheusEnabled: !draft.observability.prometheusEnabled } })}
          />
          <div className="flex justify-end">
            <Button onClick={() => save({ observability: draft.observability })}>保存 Observability</Button>
          </div>
        </Section>

        <Section title="⑦ Localization" description="默认语言与时区">
          <div>
            <div className="text-m3-label-m text-on-surface-variant">默认语言</div>
            <div className="mt-1">
              <Segmented
                value={draft.localization.defaultLocale}
                onChange={(v) => setDraft({ ...draft, localization: { ...draft.localization, defaultLocale: v } })}
                options={[
                  { value: "zh-Hans", label: "简体中文" },
                  { value: "en", label: "English" },
                ]}
              />
            </div>
          </div>
          <TextField
            label="时区"
            value={draft.localization.timezone}
            onChange={(e) => setDraft({ ...draft, localization: { ...draft.localization, timezone: e.target.value } })}
          />
          <div className="flex justify-end">
            <Button onClick={() => save({ localization: draft.localization })}>保存 Localization</Button>
          </div>
        </Section>
      </div>

      {issueDialog && (
        <TokenIssueDialog
          onClose={() => setIssueDialog(false)}
          onDone={() => {
            setIssueDialog(false);
            refresh();
          }}
        />
      )}
    </AdminShell>
  );
}

function Section({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return (
    <Card variant="filled" className="p-6">
      <div className="mb-4">
        <CardTitle>{title}</CardTitle>
        <div className="mt-1 text-m3-body-s text-on-surface-variant">{description}</div>
      </div>
      <div className="space-y-4">{children}</div>
    </Card>
  );
}

function ChipInput({
  label,
  values,
  onChange,
  placeholder,
}: {
  label: string;
  values: string[];
  onChange: (v: string[]) => void;
  placeholder?: string;
}) {
  const [input, setInput] = React.useState("");
  return (
    <div>
      <div className="mb-1 text-m3-label-m text-on-surface-variant">{label}</div>
      <div className="flex flex-wrap gap-2 rounded-m3-xs border border-outline p-2">
        {values.map((v) => (
          <Chip key={v} selected variant="input" onRemove={() => onChange(values.filter((x) => x !== v))}>
            {v}
          </Chip>
        ))}
        <input
          value={input}
          placeholder={placeholder}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && input.trim()) {
              e.preventDefault();
              onChange([...values, input.trim()]);
              setInput("");
            }
          }}
          className="min-w-32 flex-1 bg-transparent px-2 text-m3-body-m outline-none"
        />
      </div>
    </div>
  );
}

function TokenTable({ tokens, onRevoke }: { tokens: AdminToken[]; onRevoke: (id: string) => void }) {
  return (
    <div className="overflow-hidden rounded-m3-sm border border-outline-variant">
      <table className="w-full text-left text-m3-body-s">
        <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
          <tr>
            <th className="px-3 py-2">Label</th>
            <th className="px-3 py-2">Scope</th>
            <th className="px-3 py-2">Prefix</th>
            <th className="px-3 py-2">创建</th>
            <th className="px-3 py-2">最近使用</th>
            <th className="px-3 py-2"></th>
          </tr>
        </thead>
        <tbody>
          {tokens.length === 0 && (
            <tr><td colSpan={6} className="px-3 py-4 text-center text-on-surface-variant">还没有签发 token</td></tr>
          )}
          {tokens.map((t) => (
            <tr key={t.id} className="border-t border-outline-variant">
              <td className="px-3 py-2">{t.label}</td>
              <td className="px-3 py-2"><Badge tone={t.scope === "admin" ? "warn" : "info"}>{t.scope}</Badge></td>
              <td className="px-3 py-2 font-mono">{t.prefix}</td>
              <td className="px-3 py-2">{new Date(t.createdAt).toLocaleDateString()}</td>
              <td className="px-3 py-2">{t.lastUsedAt ? new Date(t.lastUsedAt).toLocaleString() : "—"}</td>
              <td className="px-3 py-2 text-right">
                {t.revoked ? <Badge tone="error">revoked</Badge> : <Button variant="text" onClick={() => onRevoke(t.id)}>吊销</Button>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
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
    <Dialog
      open
      onClose={issued ? onDone : onClose}
      title={issued ? "Token 已签发 — 仅显示一次" : "签发 bearer token"}
      actions={
        issued ? (
          <Button onClick={onDone}>完成</Button>
        ) : (
          <>
            <Button variant="text" onClick={onClose}>取消</Button>
            <Button onClick={submit} loading={busy} disabled={!label}>签发</Button>
          </>
        )
      }
    >
      {issued ? (
        <div className="space-y-2">
          <Banner tone="warn">关闭后无法再次显示，请立即复制保存。</Banner>
          <pre className="break-all rounded-m3-sm bg-surface-container-high p-3 font-mono text-m3-body-s">{issued}</pre>
        </div>
      ) : (
        <div className="space-y-3">
          <TextField label="标签" value={label} onChange={(e) => setLabel(e.target.value)} />
          <div>
            <div className="text-m3-label-m text-on-surface-variant">Scope</div>
            <div className="mt-1 flex gap-2">
              <Chip selected={scope === "admin"} onClick={() => setScope("admin")}>Admin</Chip>
              <Chip selected={scope === "client"} onClick={() => setScope("client")}>Client</Chip>
            </div>
          </div>
          <Slider
            label="每分钟请求上限"
            value={rpm}
            min={0}
            max={3000}
            step={10}
            valueLabel={`${rpm}/min`}
            onChange={setRpm}
          />
        </div>
      )}
    </Dialog>
  );
}
