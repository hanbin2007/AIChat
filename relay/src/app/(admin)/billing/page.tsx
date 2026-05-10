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
import Slider from "@mui/material/Slider";
import Switch from "@mui/material/Switch";
import FormControlLabel from "@mui/material/FormControlLabel";
import Button from "@mui/material/Button";
import Alert from "@mui/material/Alert";
import AlertTitle from "@mui/material/AlertTitle";
import Chip from "@mui/material/Chip";
import TextField from "@mui/material/TextField";
import Select from "@mui/material/Select";
import MenuItem from "@mui/material/MenuItem";
import FormControl from "@mui/material/FormControl";
import InputLabel from "@mui/material/InputLabel";
import LinearProgress from "@mui/material/LinearProgress";
import Grid from "@mui/material/Grid2";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import Paper from "@mui/material/Paper";
import AddCircleIcon from "@mui/icons-material/AddCircle";
import DeleteIcon from "@mui/icons-material/Delete";
import { AppShell } from "@/components/shell/app-shell";
import { useSnackbar } from "@/components/snackbar-provider";
import type { MeteringPolicy, MeteringRate, Plan, Transaction } from "@/lib/billing/types";
import { creditsForUsage } from "@/lib/billing/metering";

type TabKey = "plans" | "policy" | "transactions";

interface Snapshot {
  policy: MeteringPolicy;
  plans: Plan[];
  transactions: Record<string, Transaction>;
}

export default function BillingStudioPage() {
  const snack = useSnackbar();
  const [tab, setTab] = React.useState<TabKey>("policy");
  const [remote, setRemote] = React.useState<Snapshot | null>(null);
  const [policy, setPolicy] = React.useState<MeteringPolicy | null>(null);
  const [plans, setPlans] = React.useState<Plan[]>([]);
  const dirty =
    policy && remote
      ? JSON.stringify({ policy, plans }) !==
        JSON.stringify({ policy: remote.policy, plans: remote.plans })
      : false;

  const refresh = React.useCallback(async () => {
    const res = await fetch("/api/admin/billing");
    const data = await res.json();
    setRemote(data);
    setPolicy(data.policy);
    setPlans(data.plans);
  }, []);

  React.useEffect(() => {
    refresh();
  }, [refresh]);

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
    <AppShell title="Billing Studio" breadcrumb={["Billing"]}>
      <Box sx={{ p: 3 }}>
        <Stack spacing={2}>
          {dirty && (
            <Alert
              severity="warning"
              action={
                <Stack direction="row" spacing={1}>
                  <Button variant="text" size="small" onClick={refresh}>
                    放弃
                  </Button>
                  <Button size="small" onClick={save}>
                    保存
                  </Button>
                </Stack>
              }
            >
              <AlertTitle>尚未保存的变更</AlertTitle>
              策略变更在保存前不会生效。
            </Alert>
          )}

          <Tabs value={tab} onChange={(_, v) => setTab(v as TabKey)}>
            <Tab value="plans" label="Plans" />
            <Tab value="policy" label="Pricing Policy" />
            <Tab value="transactions" label="Transactions" />
          </Tabs>

          {tab === "policy" && policy && <PricingStudio policy={policy} onChange={setPolicy} />}
          {tab === "plans" && <PlansGrid plans={plans} onChange={setPlans} />}
          {tab === "transactions" && remote && (
            <TransactionList transactions={Object.values(remote.transactions ?? {})} />
          )}
        </Stack>
      </Box>
    </AppShell>
  );
}

function PricingStudio({
  policy,
  onChange,
}: {
  policy: MeteringPolicy;
  onChange: (p: MeteringPolicy) => void;
}) {
  return (
    <Grid container spacing={2}>
      <Grid size={{ xs: 12, lg: 8 }}>
        <Stack spacing={2}>
          <CreditCalculator policy={policy} />
          <Grid container spacing={2}>
            {policy.rates.map((rate, i) => (
              <Grid key={rate.modelID} size={{ xs: 12, md: 6 }}>
                <RateCard
                  rate={rate}
                  onChange={(r) => {
                    const next = {
                      ...policy,
                      rates: policy.rates.map((x, j) => (j === i ? r : x)),
                    };
                    onChange(next);
                  }}
                />
              </Grid>
            ))}
          </Grid>
        </Stack>
      </Grid>
      <Grid size={{ xs: 12, lg: 4 }}>
        <TrialPolicyCard policy={policy} onChange={onChange} />
      </Grid>
    </Grid>
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
    <Card>
      <CardHeader
        title="Credit 计算器"
        titleTypographyProps={{ variant: "subtitle1" }}
        action={
          <FormControl size="small" sx={{ minWidth: 220 }}>
            <InputLabel>Model</InputLabel>
            <Select label="Model" value={model} onChange={(e) => setModel(e.target.value)}>
              {policy.rates.map((r) => (
                <MenuItem key={r.modelID} value={r.modelID}>
                  {r.modelID}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        }
      />
      <CardContent>
        <Grid container spacing={3}>
          <Grid size={{ xs: 12, md: 6 }}>
            <Stack spacing={2}>
              <SliderField
                label="Input tokens"
                value={input}
                onChange={setInput}
                min={0}
                max={300_000}
                step={100}
                valueLabel={input.toLocaleString()}
              />
              <SliderField
                label="Output tokens"
                value={output}
                onChange={setOutput}
                min={0}
                max={100_000}
                step={100}
                valueLabel={output.toLocaleString()}
              />
              <SliderField
                label="Search 调用数"
                value={search}
                onChange={setSearch}
                min={0}
                max={20}
                valueLabel={String(search)}
              />
              <FormControlLabel
                control={<Switch checked={audio} onChange={() => setAudio((v) => !v)} />}
                label="音频输入"
              />
            </Stack>
          </Grid>
          <Grid size={{ xs: 12, md: 6 }}>
            <Box
              sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                bgcolor: "primary.main",
                color: "primary.contrastText",
                borderRadius: 3,
                p: 2,
              }}
            >
              <Typography variant="caption" sx={{ opacity: 0.85 }}>
                总计
              </Typography>
              <Typography variant="h3" sx={{ fontWeight: 600 }}>
                {credits.toLocaleString()}
              </Typography>
              <Typography variant="body2">
                credits · ${usd.toFixed(4)}
              </Typography>
            </Box>
            <Stack spacing={1.5} sx={{ mt: 2 }}>
              <Bar label="Input" value={inputCost} total={total} color="primary" />
              <Bar label="Output" value={outputCost} total={total} color="secondary" />
              <Bar label="Search" value={searchCost} total={total} color="info" />
            </Stack>
          </Grid>
        </Grid>
      </CardContent>
    </Card>
  );
}

function Bar({
  label,
  value,
  total,
  color,
}: {
  label: string;
  value: number;
  total: number;
  color: "primary" | "secondary" | "info";
}) {
  const pct = Math.min(100, Math.round((value / total) * 100));
  return (
    <Box>
      <Stack direction="row" justifyContent="space-between" alignItems="baseline">
        <Typography variant="caption" sx={{ color: "text.secondary" }}>
          {label}
        </Typography>
        <Typography variant="caption" sx={{ fontFamily: "monospace" }}>
          {Math.ceil(value)} credits
        </Typography>
      </Stack>
      <LinearProgress
        variant="determinate"
        value={pct}
        color={color}
        sx={{ mt: 0.5, height: 6, borderRadius: 3 }}
      />
    </Box>
  );
}

function RateCard({ rate, onChange }: { rate: MeteringRate; onChange: (r: MeteringRate) => void }) {
  const hasOver200k = rate.inputCreditsPerMillionOver200k !== undefined;
  return (
    <Card sx={{ height: "100%" }}>
      <CardContent>
        <Typography variant="subtitle2">{rate.modelID}</Typography>
        <Typography variant="caption" sx={{ color: "text.secondary" }}>
          每 1M tokens 的 credits 消耗
        </Typography>
        <Stack spacing={2} sx={{ mt: 2 }}>
          <SliderField
            label="Input (standard)"
            value={rate.inputCreditsPerMillion}
            min={0}
            max={10000}
            step={50}
            valueLabel={rate.inputCreditsPerMillion.toLocaleString()}
            onChange={(v) => onChange({ ...rate, inputCreditsPerMillion: v })}
          />
          {hasOver200k && (
            <SliderField
              label="Input (>200k)"
              value={rate.inputCreditsPerMillionOver200k ?? 0}
              min={0}
              max={20000}
              step={50}
              valueLabel={(rate.inputCreditsPerMillionOver200k ?? 0).toLocaleString()}
              onChange={(v) => onChange({ ...rate, inputCreditsPerMillionOver200k: v })}
            />
          )}
          <SliderField
            label="Output"
            value={rate.outputCreditsPerMillion}
            min={0}
            max={30000}
            step={100}
            valueLabel={rate.outputCreditsPerMillion.toLocaleString()}
            onChange={(v) => onChange({ ...rate, outputCreditsPerMillion: v })}
          />
          <SliderField
            label="Search surcharge"
            value={rate.searchSurchargeCredits}
            min={0}
            max={100}
            valueLabel={String(rate.searchSurchargeCredits)}
            onChange={(v) => onChange({ ...rate, searchSurchargeCredits: v })}
          />
          {rate.audioInputCreditsPerMillion !== undefined && (
            <SliderField
              label="Audio input"
              value={rate.audioInputCreditsPerMillion}
              min={0}
              max={5000}
              step={50}
              valueLabel={rate.audioInputCreditsPerMillion.toLocaleString()}
              onChange={(v) => onChange({ ...rate, audioInputCreditsPerMillion: v })}
            />
          )}
          <FormControlLabel
            control={
              <Switch
                checked={hasOver200k}
                onChange={() => {
                  if (hasOver200k) {
                    const { inputCreditsPerMillionOver200k, outputCreditsPerMillionOver200k, ...rest } =
                      rate;
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
            }
            label="支持 >200k tier"
          />
        </Stack>
      </CardContent>
    </Card>
  );
}

function TrialPolicyCard({
  policy,
  onChange,
}: {
  policy: MeteringPolicy;
  onChange: (p: MeteringPolicy) => void;
}) {
  return (
    <Card sx={{ bgcolor: "action.hover", position: "sticky", top: 80 }}>
      <CardHeader
        title="经济模型 & 试用"
        subheader="改变后会影响所有后续请求与新试用账户。"
        titleTypographyProps={{ variant: "subtitle1" }}
        subheaderTypographyProps={{ variant: "caption" }}
      />
      <CardContent>
        <Stack spacing={2}>
          <SliderField
            label="Credit → USD 汇率 (USD per 1000 credits)"
            value={policy.creditBudgetUSDPer1000Credits}
            min={0.5}
            max={20}
            step={0.5}
            valueLabel={`$${policy.creditBudgetUSDPer1000Credits.toFixed(1)}`}
            onChange={(v) => onChange({ ...policy, creditBudgetUSDPer1000Credits: v })}
          />
          <SliderField
            label="Credit multiplier"
            value={policy.creditMultiplier * 100}
            min={10}
            max={500}
            step={5}
            valueLabel={`${(policy.creditMultiplier * 100).toFixed(0)}%`}
            onChange={(v) => onChange({ ...policy, creditMultiplier: v / 100 })}
          />
          <SliderField
            label="Trial credits"
            value={policy.trialCredits}
            min={0}
            max={5000}
            step={50}
            valueLabel={policy.trialCredits.toLocaleString()}
            onChange={(v) => onChange({ ...policy, trialCredits: v })}
          />
          <SliderField
            label="Trial 天数"
            value={policy.trialDurationDays}
            min={0}
            max={30}
            valueLabel={`${policy.trialDurationDays} 天`}
            onChange={(v) => onChange({ ...policy, trialDurationDays: v })}
          />
          <SliderField
            label="低余额阈值"
            value={policy.lowBalanceThresholdCredits}
            min={0}
            max={5000}
            step={50}
            valueLabel={policy.lowBalanceThresholdCredits.toLocaleString()}
            onChange={(v) => onChange({ ...policy, lowBalanceThresholdCredits: v })}
          />
          <SliderField
            label="每账户最大绑定设备数"
            value={policy.maxBoundDevices}
            min={1}
            max={20}
            valueLabel={String(policy.maxBoundDevices)}
            onChange={(v) => onChange({ ...policy, maxBoundDevices: v })}
          />
          <Box sx={{ bgcolor: "background.paper", borderRadius: 2, p: 1.5 }}>
            <Typography variant="caption" sx={{ color: "text.secondary" }}>
              新设备首次激活将获得{" "}
              <strong>{policy.trialCredits.toLocaleString()}</strong> credits， 有效期{" "}
              <strong>{policy.trialDurationDays}</strong> 天；余额低于{" "}
              <strong>{policy.lowBalanceThresholdCredits.toLocaleString()}</strong> 触发提示；
              每账户最多绑定 <strong>{policy.maxBoundDevices}</strong> 台设备。
            </Typography>
          </Box>
        </Stack>
      </CardContent>
    </Card>
  );
}

function PlansGrid({ plans, onChange }: { plans: Plan[]; onChange: (p: Plan[]) => void }) {
  return (
    <Grid container spacing={2}>
      {plans.map((p, i) => (
        <Grid key={p.id} size={{ xs: 12, md: 6, xl: 4 }}>
          <Card sx={{ height: "100%" }}>
            <CardContent>
              <Stack spacing={2}>
                <TextField
                  label="ID"
                  value={p.id}
                  onChange={(e) =>
                    onChange(plans.map((x, j) => (j === i ? { ...x, id: e.target.value } : x)))
                  }
                />
                <TextField
                  label="标题"
                  value={p.title}
                  onChange={(e) =>
                    onChange(plans.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))
                  }
                />
                <TextField
                  label="Product ID"
                  value={p.productID}
                  onChange={(e) =>
                    onChange(
                      plans.map((x, j) => (j === i ? { ...x, productID: e.target.value } : x)),
                    )
                  }
                />
                <TextField
                  label="价格 (USD)"
                  type="number"
                  value={p.priceUSD}
                  onChange={(e) =>
                    onChange(
                      plans.map((x, j) =>
                        j === i ? { ...x, priceUSD: Number(e.target.value) || 0 } : x,
                      ),
                    )
                  }
                />
                <TextField
                  label="月度 credits"
                  type="number"
                  value={p.monthlyCredits}
                  onChange={(e) =>
                    onChange(
                      plans.map((x, j) =>
                        j === i ? { ...x, monthlyCredits: Number(e.target.value) || 0 } : x,
                      ),
                    )
                  }
                />
                <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                  <Button
                    variant="text"
                    color="error"
                    startIcon={<DeleteIcon />}
                    onClick={() => onChange(plans.filter((_, j) => j !== i))}
                  >
                    删除
                  </Button>
                </Box>
              </Stack>
            </CardContent>
          </Card>
        </Grid>
      ))}
      <Grid size={{ xs: 12, md: 6, xl: 4 }}>
        <Card
          variant="outlined"
          sx={{
            height: "100%",
            minHeight: 280,
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: "text.secondary",
            borderStyle: "dashed",
            "&:hover": { bgcolor: "action.hover" },
          }}
          onClick={() =>
            onChange([
              ...plans,
              {
                id: `plan_${Date.now()}`,
                title: "新套餐",
                productID: "",
                priceUSD: 0,
                monthlyCredits: 0,
              },
            ])
          }
        >
          <Stack alignItems="center">
            <AddCircleIcon sx={{ fontSize: 32 }} />
            <Typography variant="body2" sx={{ mt: 1 }}>
              添加套餐
            </Typography>
          </Stack>
        </Card>
      </Grid>
    </Grid>
  );
}

function TransactionList({ transactions }: { transactions: Transaction[] }) {
  return (
    <Card>
      <TableContainer component={Paper} variant="outlined" sx={{ boxShadow: "none", border: 0 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>Transaction ID</TableCell>
              <TableCell>Product</TableCell>
              <TableCell>Env</TableCell>
              <TableCell>Purchased</TableCell>
              <TableCell>Expires</TableCell>
              <TableCell>Revoked</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {transactions.length === 0 && (
              <TableRow>
                <TableCell colSpan={6} align="center" sx={{ color: "text.secondary", py: 5 }}>
                  没有交易记录
                </TableCell>
              </TableRow>
            )}
            {transactions.map((t) => (
              <TableRow key={t.transactionID} hover>
                <TableCell sx={{ fontFamily: "monospace", fontSize: "0.75rem" }}>
                  {t.transactionID}
                </TableCell>
                <TableCell>{t.productID}</TableCell>
                <TableCell>{t.environment}</TableCell>
                <TableCell>
                  {t.purchaseDate ? new Date(t.purchaseDate).toLocaleDateString() : "—"}
                </TableCell>
                <TableCell>
                  {t.expirationDate ? new Date(t.expirationDate).toLocaleDateString() : "—"}
                </TableCell>
                <TableCell>
                  <Chip
                    size="small"
                    color={t.revokedDate ? "error" : "success"}
                    label={t.revokedDate ? "revoked" : "ok"}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
    </Card>
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
