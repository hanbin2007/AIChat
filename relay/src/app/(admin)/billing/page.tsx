"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Slider from "@mui/material/Slider";
import Switch from "@mui/material/Switch";
import FormControlLabel from "@mui/material/FormControlLabel";
import LinearProgress from "@mui/material/LinearProgress";
import Button from "@mui/material/Button";
import TextField from "@mui/material/TextField";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Alert from "@mui/material/Alert";
import AlertTitle from "@mui/material/AlertTitle";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import Chip from "@mui/material/Chip";
import AddRounded from "@mui/icons-material/AddRounded";
import DeleteRounded from "@mui/icons-material/DeleteRounded";
import RefreshRounded from "@mui/icons-material/RefreshRounded";
import { AppShell } from "@/components/shell/app-shell";
import { useSnackbar } from "@/components/snackbar-provider";
import type { MeteringPolicy, Plan, MeteringRate } from "@/lib/billing/types";

type TabKey = "plans" | "policy" | "transactions";

interface BillingResponse {
  policy: MeteringPolicy;
  plans: Plan[];
}

export default function BillingPage() {
  const snackbar = useSnackbar();
  const [tab, setTab] = useState<TabKey>("policy");
  const [data, setData] = useState<BillingResponse | null>(null);
  const [policy, setPolicy] = useState<MeteringPolicy | null>(null);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [busy, setBusy] = useState(false);

  // Calculator state
  const [calcInput, setCalcInput] = useState(2000);
  const [calcOutput, setCalcOutput] = useState(800);
  const [calcSearch, setCalcSearch] = useState(0);
  const [calcAudio, setCalcAudio] = useState(false);

  const load = useCallback(async () => {
    const res = await fetch("/api/admin/billing");
    if (!res.ok) {
      snackbar.push({ message: "拉取计费数据失败", severity: "error" });
      return;
    }
    const json = (await res.json()) as BillingResponse;
    setData(json);
    setPolicy(JSON.parse(JSON.stringify(json.policy)));
    setPlans(JSON.parse(JSON.stringify(json.plans)));
  }, [snackbar]);

  useEffect(() => {
    void load();
  }, [load]);

  const dirty = useMemo(() => {
    if (!data || !policy) return false;
    return (
      JSON.stringify(policy) !== JSON.stringify(data.policy) ||
      JSON.stringify(plans) !== JSON.stringify(data.plans)
    );
  }, [data, policy, plans]);

  const save = async () => {
    if (!policy) return;
    setBusy(true);
    try {
      const res = await fetch("/api/admin/billing/policy", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ policy, plans }),
      });
      if (res.ok) {
        snackbar.push({ message: "已保存", severity: "success" });
        void load();
      } else {
        snackbar.push({ message: "保存失败", severity: "error" });
      }
    } finally {
      setBusy(false);
    }
  };

  const discard = () => {
    if (!data) return;
    setPolicy(JSON.parse(JSON.stringify(data.policy)));
    setPlans(JSON.parse(JSON.stringify(data.plans)));
  };

  const calc = useMemo(() => {
    if (!policy || policy.rates.length === 0) {
      return { input: 0, output: 0, search: 0, audio: 0, total: 0, usd: 0 };
    }
    const rate = policy.rates[0];
    const inputCredits = (calcInput / 1_000_000) * rate.inputCreditsPerMillion;
    const outputCredits = (calcOutput / 1_000_000) * rate.outputCreditsPerMillion;
    const searchCredits = calcSearch * rate.searchSurchargeCredits;
    const audioCredits = calcAudio
      ? (calcInput / 1_000_000) * (rate.audioInputCreditsPerMillion ?? 0)
      : 0;
    const total =
      (inputCredits + outputCredits + searchCredits + audioCredits) * policy.creditMultiplier;
    const usd = total * (policy.creditBudgetUSDPer1000Credits / 1000);
    return { input: inputCredits, output: outputCredits, search: searchCredits, audio: audioCredits, total, usd };
  }, [policy, calcInput, calcOutput, calcSearch, calcAudio]);

  return (
    <AppShell
      title="计费工作室"
      breadcrumb={[{ label: "AIChat Relay", href: "/dashboard" }, { label: "计费工作室" }]}
      actions={
        <Tooltip title="刷新">
          <IconButton aria-label="刷新" onClick={() => void load()}>
            <RefreshRounded />
          </IconButton>
        </Tooltip>
      }
    >
      <Stack spacing={2}>
        {dirty ? (
          <Alert
            severity="warning"
            action={
              <Stack direction="row" spacing={1}>
                <Button color="inherit" size="small" onClick={discard} disabled={busy}>
                  放弃
                </Button>
                <Button variant="contained" size="small" onClick={save} disabled={busy}>
                  {busy ? "保存中…" : "保存"}
                </Button>
              </Stack>
            }
          >
            <AlertTitle>有未保存的更改</AlertTitle>
            修改还未生效，记得点击保存
          </Alert>
        ) : null}

        <Card>
          <Box sx={{ borderBottom: 1, borderColor: "divider" }}>
            <Tabs value={tab} onChange={(_e, v: TabKey) => setTab(v)}>
              <Tab value="plans" label={`Plans (${plans.length})`} />
              <Tab value="policy" label="Pricing Policy" />
              <Tab value="transactions" label="Transactions" />
            </Tabs>
          </Box>

          <Box sx={{ p: { xs: 2, md: 3 } }}>
            {tab === "policy" && policy ? (
              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", lg: "2fr 1fr" },
                  gap: 3,
                }}
              >
                <Stack spacing={3}>
                  <Card variant="outlined">
                    <CardHeader title="Credit Calculator" subheader="按第一条 metering rate 估算" />
                    <CardContent>
                      <Stack spacing={2}>
                        <SliderField
                          label={`输入 tokens · ${calcInput}`}
                          value={calcInput}
                          min={0}
                          max={1_000_000}
                          step={1000}
                          onChange={setCalcInput}
                        />
                        <SliderField
                          label={`输出 tokens · ${calcOutput}`}
                          value={calcOutput}
                          min={0}
                          max={500_000}
                          step={500}
                          onChange={setCalcOutput}
                        />
                        <SliderField
                          label={`搜索次数 · ${calcSearch}`}
                          value={calcSearch}
                          min={0}
                          max={20}
                          step={1}
                          onChange={setCalcSearch}
                        />
                        <FormControlLabel
                          control={
                            <Switch
                              checked={calcAudio}
                              onChange={(e) => setCalcAudio(e.target.checked)}
                            />
                          }
                          label="包含音频"
                        />
                        <Box sx={{ p: 2, bgcolor: "action.hover", borderRadius: 1 }}>
                          <Typography
                            variant="h4"
                            sx={{ fontFamily: "var(--font-mono)", fontWeight: 700 }}
                          >
                            {calc.total.toFixed(2)} credits
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            ≈ ${calc.usd.toFixed(4)}
                          </Typography>
                        </Box>
                        <ShareBar label="输入" value={calc.input} total={calc.total} />
                        <ShareBar label="输出" value={calc.output} total={calc.total} />
                        <ShareBar label="搜索" value={calc.search} total={calc.total} />
                        {calcAudio ? (
                          <ShareBar label="音频" value={calc.audio} total={calc.total} />
                        ) : null}
                      </Stack>
                    </CardContent>
                  </Card>

                  <Box
                    sx={{
                      display: "grid",
                      gridTemplateColumns: { xs: "1fr", md: "1fr 1fr" },
                      gap: 2,
                    }}
                  >
                    {policy.rates.map((rate, idx) => (
                      <RateCard
                        key={rate.modelID}
                        rate={rate}
                        onChange={(next) =>
                          setPolicy((p) =>
                            p
                              ? {
                                  ...p,
                                  rates: p.rates.map((r, i) => (i === idx ? next : r)),
                                }
                              : p,
                          )
                        }
                      />
                    ))}
                  </Box>
                </Stack>

                <Box sx={{ position: { lg: "sticky" }, top: { lg: 24 } }}>
                  <Card variant="outlined">
                    <CardHeader title="Trial Policy" />
                    <CardContent>
                      <Stack spacing={2}>
                        <SliderField
                          label={`Credit / USD 比率 · ${policy.creditBudgetUSDPer1000Credits.toFixed(2)} / 1000`}
                          value={policy.creditBudgetUSDPer1000Credits}
                          min={0.1}
                          max={20}
                          step={0.1}
                          onChange={(v) =>
                            setPolicy({ ...policy, creditBudgetUSDPer1000Credits: v })
                          }
                        />
                        <SliderField
                          label={`Credit 倍率 · ×${policy.creditMultiplier.toFixed(2)}`}
                          value={policy.creditMultiplier}
                          min={0.5}
                          max={3}
                          step={0.05}
                          onChange={(v) => setPolicy({ ...policy, creditMultiplier: v })}
                        />
                        <SliderField
                          label={`试用 credits · ${policy.trialCredits}`}
                          value={policy.trialCredits}
                          min={0}
                          max={5000}
                          step={50}
                          onChange={(v) => setPolicy({ ...policy, trialCredits: v })}
                        />
                        <SliderField
                          label={`试用天数 · ${policy.trialDurationDays}`}
                          value={policy.trialDurationDays}
                          min={1}
                          max={90}
                          step={1}
                          onChange={(v) => setPolicy({ ...policy, trialDurationDays: v })}
                        />
                        <SliderField
                          label={`低额阈值 · ${policy.lowBalanceThresholdCredits}`}
                          value={policy.lowBalanceThresholdCredits}
                          min={0}
                          max={1000}
                          step={10}
                          onChange={(v) =>
                            setPolicy({ ...policy, lowBalanceThresholdCredits: v })
                          }
                        />
                        <SliderField
                          label={`绑定设备上限 · ${policy.maxBoundDevices}`}
                          value={policy.maxBoundDevices}
                          min={1}
                          max={10}
                          step={1}
                          onChange={(v) => setPolicy({ ...policy, maxBoundDevices: v })}
                        />
                      </Stack>
                    </CardContent>
                  </Card>
                </Box>
              </Box>
            ) : null}

            {tab === "plans" ? (
              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
                  gap: 2,
                }}
              >
                {plans.map((plan, idx) => (
                  <Card key={plan.id} variant="outlined">
                    <CardContent>
                      <Stack spacing={1.5}>
                        <Stack direction="row" justifyContent="space-between" alignItems="center">
                          <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                            {plan.title || "未命名"}
                          </Typography>
                          <IconButton
                            size="small"
                            aria-label="删除"
                            onClick={() =>
                              setPlans((ps) => ps.filter((_, i) => i !== idx))
                            }
                          >
                            <DeleteRounded fontSize="small" />
                          </IconButton>
                        </Stack>
                        <TextField
                          label="标题"
                          size="small"
                          value={plan.title}
                          onChange={(e) =>
                            setPlans((ps) =>
                              ps.map((p, i) => (i === idx ? { ...p, title: e.target.value } : p)),
                            )
                          }
                        />
                        <TextField
                          label="ID"
                          size="small"
                          value={plan.id}
                          onChange={(e) =>
                            setPlans((ps) =>
                              ps.map((p, i) => (i === idx ? { ...p, id: e.target.value } : p)),
                            )
                          }
                        />
                        <TextField
                          label="Product ID"
                          size="small"
                          value={plan.productID}
                          onChange={(e) =>
                            setPlans((ps) =>
                              ps.map((p, i) =>
                                i === idx ? { ...p, productID: e.target.value } : p,
                              ),
                            )
                          }
                        />
                        <TextField
                          label="价格 (USD)"
                          size="small"
                          type="number"
                          value={plan.priceUSD}
                          onChange={(e) =>
                            setPlans((ps) =>
                              ps.map((p, i) =>
                                i === idx ? { ...p, priceUSD: Number(e.target.value) } : p,
                              ),
                            )
                          }
                        />
                        <TextField
                          label="月度 Credits"
                          size="small"
                          type="number"
                          value={plan.monthlyCredits}
                          onChange={(e) =>
                            setPlans((ps) =>
                              ps.map((p, i) =>
                                i === idx ? { ...p, monthlyCredits: Number(e.target.value) } : p,
                              ),
                            )
                          }
                        />
                      </Stack>
                    </CardContent>
                  </Card>
                ))}
                <Card
                  variant="outlined"
                  sx={{
                    border: "1px dashed",
                    borderColor: "divider",
                    minHeight: 240,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <Button
                    startIcon={<AddRounded />}
                    onClick={() =>
                      setPlans((ps) => [
                        ...ps,
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
                    添加套餐
                  </Button>
                </Card>
              </Box>
            ) : null}

            {tab === "transactions" ? <TransactionsTab /> : null}
          </Box>
        </Card>
      </Stack>
    </AppShell>
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

function ShareBar({ label, value, total }: { label: string; value: number; total: number }) {
  const pct = total > 0 ? (value / total) * 100 : 0;
  return (
    <Box>
      <Stack direction="row" justifyContent="space-between" sx={{ mb: 0.5 }}>
        <Typography variant="caption" color="text.secondary">
          {label}
        </Typography>
        <Typography variant="caption" sx={{ fontFamily: "var(--font-mono)" }}>
          {value.toFixed(2)} ({pct.toFixed(1)}%)
        </Typography>
      </Stack>
      <LinearProgress variant="determinate" value={pct} />
    </Box>
  );
}

function RateCard({
  rate,
  onChange,
}: {
  rate: MeteringRate;
  onChange: (next: MeteringRate) => void;
}) {
  return (
    <Card variant="outlined">
      <CardContent>
        <Typography
          variant="subtitle2"
          sx={{ fontFamily: "var(--font-mono)", fontWeight: 700, mb: 1.5 }}
        >
          {rate.modelID}
        </Typography>
        <Stack spacing={1.5}>
          <TextField
            label="输入 / M tokens"
            size="small"
            type="number"
            value={rate.inputCreditsPerMillion}
            onChange={(e) =>
              onChange({ ...rate, inputCreditsPerMillion: Number(e.target.value) })
            }
          />
          <TextField
            label="输出 / M tokens"
            size="small"
            type="number"
            value={rate.outputCreditsPerMillion}
            onChange={(e) =>
              onChange({ ...rate, outputCreditsPerMillion: Number(e.target.value) })
            }
          />
          <TextField
            label="搜索附加"
            size="small"
            type="number"
            value={rate.searchSurchargeCredits}
            onChange={(e) =>
              onChange({ ...rate, searchSurchargeCredits: Number(e.target.value) })
            }
          />
        </Stack>
      </CardContent>
    </Card>
  );
}

function TransactionsTab() {
  const [transactions, setTransactions] = useState<
    Array<{
      transactionID: string;
      productID: string;
      environment: string;
      purchaseDate?: string;
      expirationDate?: string;
      revokedDate?: string;
    }>
  >([]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const res = await fetch("/api/admin/billing");
      if (!res.ok) return;
      const json = (await res.json()) as { transactions?: typeof transactions };
      if (!cancelled) setTransactions(json.transactions ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (transactions.length === 0) {
    return (
      <Box sx={{ p: 4, textAlign: "center" }}>
        <Typography variant="body2" color="text.secondary">
          暂无交易记录
        </Typography>
      </Box>
    );
  }

  return (
    <Table size="small">
      <TableHead>
        <TableRow>
          <TableCell>交易 ID</TableCell>
          <TableCell>产品</TableCell>
          <TableCell>环境</TableCell>
          <TableCell>购买于</TableCell>
          <TableCell>过期</TableCell>
          <TableCell>状态</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {transactions.map((t) => (
          <TableRow key={t.transactionID}>
            <TableCell sx={{ fontFamily: "var(--font-mono)" }}>
              {t.transactionID.slice(0, 12)}…
            </TableCell>
            <TableCell>{t.productID}</TableCell>
            <TableCell>{t.environment}</TableCell>
            <TableCell>
              {t.purchaseDate ? new Date(t.purchaseDate).toLocaleString("zh-Hans") : "—"}
            </TableCell>
            <TableCell>
              {t.expirationDate ? new Date(t.expirationDate).toLocaleString("zh-Hans") : "—"}
            </TableCell>
            <TableCell>
              {t.revokedDate ? <Chip size="small" label="已撤销" color="error" /> : <Chip size="small" label="活跃" />}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
