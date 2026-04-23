"use client";
import * as React from "react";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Banner, Button, Card, CardContent, CardHeader, CardTitle, Chip, Slider, Switch, Tabs, TextField, Icon, useSnackbar } from "@/components/m3";
import type { MeteringPolicy, MeteringRate, Plan, Transaction } from "@/lib/billing/types";
import { creditsForUsage } from "@/lib/billing/metering";
import { cn } from "@/lib/cn";

type Tab = "plans" | "policy" | "transactions";

interface Snapshot {
  policy: MeteringPolicy;
  plans: Plan[];
  transactions: Record<string, Transaction>;
}

export default function BillingStudioPage() {
  const snack = useSnackbar();
  const [tab, setTab] = React.useState<Tab>("policy");
  const [remote, setRemote] = React.useState<Snapshot | null>(null);
  const [policy, setPolicy] = React.useState<MeteringPolicy | null>(null);
  const [plans, setPlans] = React.useState<Plan[]>([]);
  const dirty = policy && remote
    ? JSON.stringify({ policy, plans }) !== JSON.stringify({ policy: remote.policy, plans: remote.plans })
    : false;

  async function refresh() {
    const res = await fetch("/api/admin/billing");
    const data = await res.json();
    setRemote(data);
    setPolicy(data.policy);
    setPlans(data.plans);
  }
  React.useEffect(() => { refresh(); }, []);

  async function save() {
    if (!policy) return;
    const res = await fetch("/api/admin/billing/policy", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ policy, plans }),
    });
    if (res.ok) {
      snack.push({ message: "已保存" });
      refresh();
    } else {
      snack.push({ message: "保存失败" });
    }
  }

  return (
    <AdminShell title="Billing Studio" breadcrumb={["Billing"]}>
      <div className="space-y-4 p-6">
        {dirty && (
          <Banner
            tone="warn"
            title="尚未保存的变更"
            actions={
              <>
                <Button variant="text" onClick={refresh}>放弃</Button>
                <Button onClick={save}>保存</Button>
              </>
            }
          >
            策略变更在保存前不会生效。
          </Banner>
        )}

        <Tabs
          value={tab}
          onChange={setTab}
          options={[
            { value: "plans", label: "Plans" },
            { value: "policy", label: "Pricing Policy" },
            { value: "transactions", label: "Transactions" },
          ]}
        />

        {tab === "policy" && policy && (
          <PricingStudio policy={policy} onChange={setPolicy} />
        )}
        {tab === "plans" && (
          <PlansGrid plans={plans} onChange={setPlans} />
        )}
        {tab === "transactions" && remote && (
          <TransactionList transactions={Object.values(remote.transactions ?? {})} />
        )}
      </div>
    </AdminShell>
  );
}

function PricingStudio({ policy, onChange }: { policy: MeteringPolicy; onChange: (p: MeteringPolicy) => void }) {
  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_360px]">
      <div className="space-y-4">
        <CreditCalculator policy={policy} />
        <div className="grid gap-4 md:grid-cols-2">
          {policy.rates.map((rate, i) => (
            <RateCard
              key={rate.modelID}
              rate={rate}
              onChange={(r) => {
                const next = { ...policy, rates: policy.rates.map((x, j) => (j === i ? r : x)) };
                onChange(next);
              }}
            />
          ))}
        </div>
      </div>
      <TrialPolicyCard policy={policy} onChange={onChange} />
    </div>
  );
}

function CreditCalculator({ policy }: { policy: MeteringPolicy }) {
  const [model, setModel] = React.useState(policy.rates[0]?.modelID ?? "");
  const [input, setInput] = React.useState(4000);
  const [output, setOutput] = React.useState(2000);
  const [search, setSearch] = React.useState(0);
  const [audio, setAudio] = React.useState(false);
  const rate = policy.rates.find((r) => r.modelID === model) ?? policy.rates[0];
  if (!rate) return null;
  const credits = creditsForUsage(policy, rate, {
    inputTokens: input,
    outputTokens: output,
    searchCount: search,
    audioInput: audio,
  });
  const usd = (credits / 1000) * policy.creditBudgetUSDPer1000Credits;

  const inputEff = audio
    ? rate.audioInputCreditsPerMillion ?? rate.inputCreditsPerMillion
    : input > 200_000 && rate.inputCreditsPerMillionOver200k
      ? rate.inputCreditsPerMillionOver200k
      : rate.inputCreditsPerMillion;
  const outputEff = rate.outputCreditsPerMillion;
  const inputCost = (input / 1e6) * inputEff * policy.creditMultiplier;
  const outputCost = (output / 1e6) * outputEff * policy.creditMultiplier;
  const searchCost = search * rate.searchSurchargeCredits * policy.creditMultiplier;
  const total = Math.max(inputCost + outputCost + searchCost, 1);

  return (
    <Card variant="elevated" className="p-5">
      <div className="flex items-center justify-between">
        <CardTitle>Credit 计算器</CardTitle>
        <select
          value={model}
          onChange={(e) => setModel(e.target.value)}
          className="rounded-m3-xs border border-outline bg-surface px-3 py-2 text-m3-body-m"
        >
          {policy.rates.map((r) => <option key={r.modelID} value={r.modelID}>{r.modelID}</option>)}
        </select>
      </div>
      <div className="mt-4 grid gap-6 md:grid-cols-2">
        <div className="space-y-4">
          <Slider label="Input tokens" value={input} onChange={setInput} min={0} max={300_000} step={100} valueLabel={input.toLocaleString()} />
          <Slider label="Output tokens" value={output} onChange={setOutput} min={0} max={100_000} step={100} valueLabel={output.toLocaleString()} />
          <Slider label="Search 调用数" value={search} onChange={setSearch} min={0} max={20} valueLabel={String(search)} />
          <Switch label="音频输入" checked={audio} onChange={() => setAudio((v) => !v)} />
        </div>
        <div>
          <div className="flex flex-col items-center justify-center rounded-m3-lg bg-primary-container p-4 text-on-primary-container">
            <div className="text-m3-label-m opacity-80">总计</div>
            <div className="text-m3-display-s font-semibold">{credits.toLocaleString()}</div>
            <div className="text-m3-label-l">credits · ${usd.toFixed(4)}</div>
          </div>
          <div className="mt-4 space-y-2">
            <Bar label="Input" value={inputCost} total={total} color="primary" />
            <Bar label="Output" value={outputCost} total={total} color="tertiary" />
            <Bar label="Search" value={searchCost} total={total} color="secondary" />
          </div>
        </div>
      </div>
    </Card>
  );
}

function Bar({ label, value, total, color }: { label: string; value: number; total: number; color: "primary" | "tertiary" | "secondary" }) {
  const pct = Math.min(100, Math.round((value / total) * 100));
  const bg = color === "primary" ? "bg-primary" : color === "tertiary" ? "bg-tertiary" : "bg-secondary";
  return (
    <div>
      <div className="flex justify-between text-m3-body-s">
        <span className="text-on-surface-variant">{label}</span>
        <span className="font-mono">{Math.ceil(value)} credits</span>
      </div>
      <div className="mt-1 h-2 rounded-full bg-surface-container-highest">
        <div className={cn("h-2 rounded-full", bg)} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

function RateCard({ rate, onChange }: { rate: MeteringRate; onChange: (r: MeteringRate) => void }) {
  const hasOver200k = rate.inputCreditsPerMillionOver200k !== undefined;
  return (
    <Card variant="outlined" className="p-4">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-m3-title-s">{rate.modelID}</div>
          <div className="text-m3-body-s text-on-surface-variant">每 1M tokens 的 credits 消耗</div>
        </div>
      </div>
      <div className="mt-4 space-y-4">
        <Slider
          label="Input (standard)"
          value={rate.inputCreditsPerMillion}
          min={0}
          max={10000}
          step={50}
          valueLabel={rate.inputCreditsPerMillion.toLocaleString()}
          onChange={(v) => onChange({ ...rate, inputCreditsPerMillion: v })}
        />
        {hasOver200k && (
          <Slider
            label="Input (>200k)"
            value={rate.inputCreditsPerMillionOver200k ?? 0}
            min={0}
            max={20000}
            step={50}
            valueLabel={(rate.inputCreditsPerMillionOver200k ?? 0).toLocaleString()}
            onChange={(v) => onChange({ ...rate, inputCreditsPerMillionOver200k: v })}
          />
        )}
        <Slider
          label="Output"
          value={rate.outputCreditsPerMillion}
          min={0}
          max={30000}
          step={100}
          valueLabel={rate.outputCreditsPerMillion.toLocaleString()}
          onChange={(v) => onChange({ ...rate, outputCreditsPerMillion: v })}
        />
        <Slider
          label="Search surcharge"
          value={rate.searchSurchargeCredits}
          min={0}
          max={100}
          valueLabel={String(rate.searchSurchargeCredits)}
          onChange={(v) => onChange({ ...rate, searchSurchargeCredits: v })}
        />
        {rate.audioInputCreditsPerMillion !== undefined && (
          <Slider
            label="Audio input"
            value={rate.audioInputCreditsPerMillion}
            min={0}
            max={5000}
            step={50}
            valueLabel={rate.audioInputCreditsPerMillion.toLocaleString()}
            onChange={(v) => onChange({ ...rate, audioInputCreditsPerMillion: v })}
          />
        )}
        <Switch
          label="支持 >200k tier"
          checked={hasOver200k}
          onChange={() => {
            if (hasOver200k) {
              const { inputCreditsPerMillionOver200k, outputCreditsPerMillionOver200k, ...rest } = rate;
              void inputCreditsPerMillionOver200k;
              void outputCreditsPerMillionOver200k;
              onChange(rest);
            } else {
              onChange({
                ...rate,
                inputCreditsPerMillionOver200k: rate.inputCreditsPerMillion * 2,
                outputCreditsPerMillionOver200k: rate.outputCreditsPerMillion * 1.5,
              });
            }
          }}
        />
      </div>
    </Card>
  );
}

function TrialPolicyCard({ policy, onChange }: { policy: MeteringPolicy; onChange: (p: MeteringPolicy) => void }) {
  return (
    <Card variant="filled" className="p-5 space-y-4 self-start">
      <div>
        <CardTitle>经济模型 & 试用</CardTitle>
        <p className="mt-1 text-m3-body-s text-on-surface-variant">改变后会影响所有后续请求与新试用账户。</p>
      </div>
      <Slider
        label="Credit → USD 汇率 (USD per 1000 credits)"
        value={policy.creditBudgetUSDPer1000Credits}
        min={0.5}
        max={20}
        step={0.5}
        valueLabel={`$${policy.creditBudgetUSDPer1000Credits.toFixed(1)}`}
        onChange={(v) => onChange({ ...policy, creditBudgetUSDPer1000Credits: v })}
      />
      <Slider
        label="Credit multiplier"
        value={policy.creditMultiplier * 100}
        min={10}
        max={500}
        step={5}
        valueLabel={`${(policy.creditMultiplier * 100).toFixed(0)}%`}
        onChange={(v) => onChange({ ...policy, creditMultiplier: v / 100 })}
      />
      <Slider
        label="Trial credits"
        value={policy.trialCredits}
        min={0}
        max={5000}
        step={50}
        valueLabel={policy.trialCredits.toLocaleString()}
        onChange={(v) => onChange({ ...policy, trialCredits: v })}
      />
      <Slider
        label="Trial 天数"
        value={policy.trialDurationDays}
        min={0}
        max={30}
        valueLabel={`${policy.trialDurationDays} 天`}
        onChange={(v) => onChange({ ...policy, trialDurationDays: v })}
      />
      <Slider
        label="低余额阈值"
        value={policy.lowBalanceThresholdCredits}
        min={0}
        max={5000}
        step={50}
        valueLabel={policy.lowBalanceThresholdCredits.toLocaleString()}
        onChange={(v) => onChange({ ...policy, lowBalanceThresholdCredits: v })}
      />
      <Slider
        label="每账户最大绑定设备数"
        value={policy.maxBoundDevices}
        min={1}
        max={20}
        valueLabel={String(policy.maxBoundDevices)}
        onChange={(v) => onChange({ ...policy, maxBoundDevices: v })}
      />
      <div className="rounded-m3-sm bg-surface-container p-3 text-m3-body-s text-on-surface-variant">
        新设备首次激活将获得 <strong>{policy.trialCredits.toLocaleString()}</strong> credits，
        有效期 <strong>{policy.trialDurationDays}</strong> 天；余额低于 <strong>{policy.lowBalanceThresholdCredits.toLocaleString()}</strong> 触发提示；
        每账户最多绑定 <strong>{policy.maxBoundDevices}</strong> 台设备。
      </div>
    </Card>
  );
}

function PlansGrid({ plans, onChange }: { plans: Plan[]; onChange: (p: Plan[]) => void }) {
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {plans.map((p, i) => (
        <Card key={p.id} variant="outlined" className="p-5">
          <div className="space-y-3">
            <TextField label="ID" value={p.id} onChange={(e) => onChange(plans.map((x, j) => j === i ? { ...x, id: e.target.value } : x))} />
            <TextField label="标题" value={p.title} onChange={(e) => onChange(plans.map((x, j) => j === i ? { ...x, title: e.target.value } : x))} />
            <TextField label="Product ID" value={p.productID} onChange={(e) => onChange(plans.map((x, j) => j === i ? { ...x, productID: e.target.value } : x))} />
            <TextField
              label="价格 (USD)"
              type="number"
              value={p.priceUSD}
              onChange={(e) => onChange(plans.map((x, j) => j === i ? { ...x, priceUSD: Number(e.target.value) || 0 } : x))}
            />
            <TextField
              label="月度 credits"
              type="number"
              value={p.monthlyCredits}
              onChange={(e) => onChange(plans.map((x, j) => j === i ? { ...x, monthlyCredits: Number(e.target.value) || 0 } : x))}
            />
            <div className="flex justify-end">
              <Button variant="text" icon="delete" onClick={() => onChange(plans.filter((_, j) => j !== i))}>删除</Button>
            </div>
          </div>
        </Card>
      ))}
      <Card
        variant="outlined"
        className="state-layer flex h-full min-h-64 cursor-pointer items-center justify-center p-5 text-on-surface-variant"
        onClick={() =>
          onChange([
            ...plans,
            { id: `plan_${Date.now()}`, title: "新套餐", productID: "", priceUSD: 0, monthlyCredits: 0 },
          ])
        }
      >
        <div className="text-center">
          <Icon name="add_circle" size={32} />
          <div className="mt-2 text-m3-body-m">添加套餐</div>
        </div>
      </Card>
    </div>
  );
}

function TransactionList({ transactions }: { transactions: Transaction[] }) {
  return (
    <Card>
      <CardContent className="p-0">
        <table className="w-full text-left text-m3-body-s">
          <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
            <tr>
              <th className="px-3 py-2">Transaction ID</th>
              <th className="px-3 py-2">Product</th>
              <th className="px-3 py-2">Env</th>
              <th className="px-3 py-2">Purchased</th>
              <th className="px-3 py-2">Expires</th>
              <th className="px-3 py-2">Revoked</th>
            </tr>
          </thead>
          <tbody>
            {transactions.length === 0 && (
              <tr><td colSpan={6} className="px-3 py-8 text-center text-on-surface-variant">没有交易记录</td></tr>
            )}
            {transactions.map((t) => (
              <tr key={t.transactionID} className="border-t border-outline-variant">
                <td className="px-3 py-2 font-mono text-m3-label-s">{t.transactionID}</td>
                <td className="px-3 py-2">{t.productID}</td>
                <td className="px-3 py-2">{t.environment}</td>
                <td className="px-3 py-2">{t.purchaseDate ? new Date(t.purchaseDate).toLocaleDateString() : "—"}</td>
                <td className="px-3 py-2">{t.expirationDate ? new Date(t.expirationDate).toLocaleDateString() : "—"}</td>
                <td className="px-3 py-2">
                  {t.revokedDate ? <Badge tone="error">revoked</Badge> : <Badge tone="success">ok</Badge>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  );
}
