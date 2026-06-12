"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { ComponentType } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import { Stack } from "@/components/lib/stack";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Button from "@mui/material/Button";
import Chip from "@mui/material/Chip";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import TextField from "@mui/material/TextField";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import Typography from "@mui/material/Typography";
import AddRounded from "@mui/icons-material/AddRounded";
import RefreshRounded from "@mui/icons-material/RefreshRounded";
import DeleteRounded from "@mui/icons-material/DeleteRounded";
import OpenInNewRounded from "@mui/icons-material/OpenInNewRounded";
import type { DataGridProps, GridColDef } from "@mui/x-data-grid";
import { useSnackbar } from "@/components/snackbar-provider";
import { useSetPageActions } from "@/components/shell/page-meta";
import type {
  Account,
  Device,
  Key,
  ActivationCode,
  PairingToken,
} from "@/lib/billing/types";

type TabKey = "accounts" | "devices" | "keys" | "codes" | "pairings";
type LoadState = "loading" | "ready" | "error";

const DataGrid = dynamic(() => import("@mui/x-data-grid").then((mod) => mod.DataGrid), {
  ssr: false,
  loading: () => <EmptyState message="正在加载表格…" />,
}) as ComponentType<DataGridProps>;

interface BillingData {
  accounts: Account[];
  devices: Device[];
  keys: Key[];
  activationCodes: ActivationCode[];
  pairingTokens: PairingToken[];
}

export default function AccountsPage() {
  const snackbar = useSnackbar();
  const [tab, setTab] = useState<TabKey>("accounts");
  const [data, setData] = useState<BillingData | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [search, setSearch] = useState("");
  const [codeDialog, setCodeDialog] = useState(false);
  const [codeForm, setCodeForm] = useState({ count: 1, credits: 100, note: "" });
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoadState("loading");
    try {
      const res = await fetch("/api/admin/billing");
      if (!res.ok) throw new Error("拉取计费数据失败");
      const json = (await res.json()) as BillingData;
      setData(json);
      setLoadState("ready");
    } catch {
      setLoadState("error");
      snackbar.push({ message: "拉取计费数据失败", severity: "error" });
    }
  }, [snackbar]);

  useEffect(() => {
    void load();
  }, [load]);

  const counts = {
    accounts: data?.accounts.length ?? 0,
    devices: data?.devices.length ?? 0,
    keys: data?.keys.length ?? 0,
    codes: data?.activationCodes.length ?? 0,
    pairings: data?.pairingTokens.length ?? 0,
  };

  const filterRows = <T,>(rows: T[], match: (row: T) => string): T[] => {
    const q = search.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) => match(r).toLowerCase().includes(q));
  };

  const accountCols = useMemo<GridColDef<Account>[]>(
    () => [
      {
        field: "displayName",
        headerName: "名称",
        flex: 1.4,
        minWidth: 220,
        renderCell: (p) => (
          <Box>
            <Typography variant="body2" sx={{ fontWeight: 600 }}>
              {p.row.displayName ?? "（未命名）"}
            </Typography>
            <Typography
              variant="caption"
              color="text.secondary"
              sx={{ fontFamily: "var(--font-mono)" }}
            >
              {p.row.accountID}
            </Typography>
          </Box>
        ),
      },
      {
        field: "state",
        headerName: "状态",
        width: 110,
        renderCell: (p) => <Chip size="small" label={p.row.state} />,
      },
      { field: "source", headerName: "来源", width: 140 },
      {
        field: "creditBalance",
        headerName: "余额",
        width: 110,
        renderCell: (p) => (
          <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
            {p.row.creditBalance}
          </Typography>
        ),
      },
      {
        field: "creditExpiresAt",
        headerName: "到期",
        width: 160,
        valueGetter: (_v, row) =>
          row.creditExpiresAt ? new Date(row.creditExpiresAt).toLocaleDateString("zh-Hans") : "—",
      },
      {
        field: "lastUsageAt",
        headerName: "最近使用",
        width: 160,
        valueGetter: (_v, row) =>
          row.lastUsageAt ? new Date(row.lastUsageAt).toLocaleString("zh-Hans") : "—",
      },
      {
        field: "actions",
        headerName: " ",
        width: 80,
        sortable: false,
        renderCell: (p) => (
          <Tooltip title="查看详情">
            <IconButton
              aria-label="查看详情"
              size="small"
              component={Link}
              href={`/accounts/${p.row.accountID}`}
            >
              <OpenInNewRounded fontSize="small" />
            </IconButton>
          </Tooltip>
        ),
      },
    ],
    [],
  );

  const deviceCols = useMemo<GridColDef<Device>[]>(
    () => [
      { field: "platform", headerName: "平台", width: 110 },
      {
        field: "alias",
        headerName: "设备",
        flex: 1,
        minWidth: 180,
        renderCell: (p) => (
          <Box>
            <Typography variant="body2" sx={{ fontWeight: 600 }}>
              {p.row.alias ?? "—"}
            </Typography>
            <Typography
              variant="caption"
              color="text.secondary"
              sx={{ fontFamily: "var(--font-mono)" }}
            >
              {p.row.deviceID}
            </Typography>
          </Box>
        ),
      },
      {
        field: "accountID",
        headerName: "所属账户",
        flex: 1,
        minWidth: 180,
        renderCell: (p) => (
          <Box
            component={Link}
            href={`/accounts/${p.row.accountID}`}
            sx={{ fontFamily: "var(--font-mono)", color: "primary.main" }}
          >
            {p.row.accountID}
          </Box>
        ),
      },
      {
        field: "lastSeenAt",
        headerName: "最近上线",
        width: 160,
        valueGetter: (_v, row) =>
          row.lastSeenAt ? new Date(row.lastSeenAt).toLocaleString("zh-Hans") : "—",
      },
    ],
    [],
  );

  const keyCols = useMemo<GridColDef<Key>[]>(
    () => [
      {
        field: "keyValue",
        headerName: "Key",
        flex: 1.2,
        minWidth: 200,
        renderCell: (p) => (
          <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
            {p.row.keyValue.slice(0, 8)}…
          </Typography>
        ),
      },
      {
        field: "accountID",
        headerName: "所属账户",
        flex: 1,
        minWidth: 180,
        renderCell: (p) => (
          <Box
            component={Link}
            href={`/accounts/${p.row.accountID}`}
            sx={{ fontFamily: "var(--font-mono)", color: "primary.main" }}
          >
            {p.row.accountID}
          </Box>
        ),
      },
      {
        field: "state",
        headerName: "状态",
        width: 110,
        renderCell: (p) => <Chip size="small" label={p.row.state} />,
      },
      { field: "source", headerName: "来源", width: 140 },
      {
        field: "issuedAt",
        headerName: "签发于",
        width: 160,
        valueGetter: (_v, row) => new Date(row.issuedAt).toLocaleString("zh-Hans"),
      },
    ],
    [],
  );

  const revokeCode = useCallback(
    async (code: string) => {
      if (!confirm(`确定要撤销激活码 ${code} 吗？`)) return;
      const res = await fetch(`/api/admin/billing/activation-codes/${code}`, {
        method: "DELETE",
      });
      if (res.ok) {
        snackbar.push({ message: "已撤销", severity: "success" });
        void load();
      } else {
        snackbar.push({ message: "撤销失败", severity: "error" });
      }
    },
    [snackbar, load],
  );

  const codeCols = useMemo<GridColDef<ActivationCode>[]>(
    () => [
      {
        field: "code",
        headerName: "激活码",
        flex: 1,
        minWidth: 180,
        renderCell: (p) => (
          <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
            {p.row.code}
          </Typography>
        ),
      },
      { field: "plan", headerName: "套餐", width: 140, valueGetter: (_v, row) => row.plan ?? "—" },
      {
        field: "credits",
        headerName: "Credits",
        width: 100,
      },
      {
        field: "state",
        headerName: "状态",
        width: 110,
        renderCell: (p) => <Chip size="small" label={p.row.state} />,
      },
      {
        field: "expiresAt",
        headerName: "过期",
        width: 160,
        valueGetter: (_v, row) =>
          row.expiresAt ? new Date(row.expiresAt).toLocaleString("zh-Hans") : "—",
      },
      { field: "note", headerName: "备注", flex: 1 },
      {
        field: "actions",
        headerName: " ",
        width: 80,
        sortable: false,
        renderCell: (p) =>
          p.row.state === "unused" ? (
            <Tooltip title="撤销">
              <IconButton
                aria-label="撤销激活码"
                size="small"
                onClick={() => void revokeCode(p.row.code)}
              >
                <DeleteRounded fontSize="small" />
              </IconButton>
            </Tooltip>
          ) : null,
      },
    ],
    [revokeCode],
  );

  const pairingCols = useMemo<GridColDef<PairingToken>[]>(
    () => [
      {
        field: "token",
        headerName: "Token",
        flex: 1,
        minWidth: 200,
        renderCell: (p) => (
          <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
            {p.row.token.slice(0, 12)}…
          </Typography>
        ),
      },
      {
        field: "accountID",
        headerName: "账户",
        flex: 1,
        minWidth: 180,
      },
      {
        field: "issuedBy",
        headerName: "由设备",
        flex: 1,
        minWidth: 180,
      },
      {
        field: "expiresAt",
        headerName: "过期",
        width: 200,
        valueGetter: (_v, row) => new Date(row.expiresAt).toLocaleString("zh-Hans"),
      },
    ],
    [],
  );

  const submitCode = async () => {
    setBusy(true);
    try {
      const res = await fetch("/api/admin/billing/activation-codes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(codeForm),
      });
      if (res.ok) {
        snackbar.push({ message: `已生成 ${codeForm.count} 个激活码`, severity: "success" });
        setCodeDialog(false);
        void load();
      } else {
        const data = (await res.json().catch(() => ({}))) as { message?: string };
        snackbar.push({ message: data.message ?? "生成失败", severity: "error" });
      }
    } finally {
      setBusy(false);
    }
  };

  useSetPageActions(
    <>
      {tab === "codes" ? (
        <Button
          startIcon={<AddRounded />}
          variant="contained"
          size="small"
          onClick={() => setCodeDialog(true)}
        >
          生成激活码
        </Button>
      ) : null}
      <Tooltip title="刷新">
        <IconButton aria-label="刷新" onClick={() => void load()}>
          <RefreshRounded />
        </IconButton>
      </Tooltip>
    </>,
    [tab],
  );

  return (
    <>
      <Card>
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          alignItems={{ md: "center" }}
          sx={{ p: 2, borderBottom: 1, borderColor: "divider" }}
        >
          <Tabs
            value={tab}
            onChange={(_e, v: TabKey) => setTab(v)}
            variant="scrollable"
            sx={{ flex: 1 }}
          >
            <Tab value="accounts" label={`账户 (${counts.accounts})`} />
            <Tab value="devices" label={`设备 (${counts.devices})`} />
            <Tab value="keys" label={`Keys (${counts.keys})`} />
            <Tab value="codes" label={`激活码 (${counts.codes})`} />
            <Tab value="pairings" label={`配对 (${counts.pairings})`} />
          </Tabs>
          <TextField
            size="small"
            label="搜索账户数据"
            placeholder="名称 / ID / 备注"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            sx={{ minWidth: 240 }}
          />
        </Stack>

        <Box sx={{ height: 600 }}>
          {loadState === "loading" ? (
            <EmptyState message="正在加载账户数据…" />
          ) : loadState === "error" ? (
            <EmptyState message="账户数据加载失败" actionLabel="重试" onAction={() => void load()} />
          ) : tab === "accounts" ? (
            <DataGrid
              rows={filterRows(data?.accounts ?? [], (r) => `${r.displayName ?? ""} ${r.accountID}`)}
              columns={accountCols as GridColDef[]}
              getRowId={(r) => r.accountID}
              density="compact"
              sx={{ border: "none" }}
            />
          ) : null}
          {tab === "devices" ? (
            <DataGrid
              rows={filterRows(data?.devices ?? [], (r) => `${r.alias ?? ""} ${r.deviceID} ${r.accountID}`)}
              columns={deviceCols as GridColDef[]}
              getRowId={(r) => r.deviceID}
              density="compact"
              sx={{ border: "none" }}
            />
          ) : null}
          {tab === "keys" ? (
            <DataGrid
              rows={filterRows(data?.keys ?? [], (r) => `${r.keyValue} ${r.accountID}`)}
              columns={keyCols as GridColDef[]}
              getRowId={(r) => r.keyID}
              density="compact"
              sx={{ border: "none" }}
            />
          ) : null}
          {tab === "codes" ? (
            <DataGrid
              rows={filterRows(data?.activationCodes ?? [], (r) => `${r.code} ${r.note ?? ""}`)}
              columns={codeCols as GridColDef[]}
              getRowId={(r) => r.code}
              density="compact"
              sx={{ border: "none" }}
            />
          ) : null}
          {tab === "pairings" ? (
            <DataGrid
              rows={filterRows(data?.pairingTokens ?? [], (r) => `${r.token} ${r.accountID}`)}
              columns={pairingCols as GridColDef[]}
              getRowId={(r) => r.token}
              density="compact"
              sx={{ border: "none" }}
            />
          ) : null}
        </Box>
      </Card>

      <Dialog open={codeDialog} onClose={() => setCodeDialog(false)} maxWidth="xs" fullWidth>
        <DialogTitle>生成激活码</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField
              label="数量"
              type="number"
              value={codeForm.count}
              onChange={(e) => setCodeForm({ ...codeForm, count: Number(e.target.value) })}
              slotProps={{ htmlInput: { min: 1, max: 100 } }}
            />
            <TextField
              label="Credits"
              type="number"
              value={codeForm.credits}
              onChange={(e) => setCodeForm({ ...codeForm, credits: Number(e.target.value) })}
            />
            <TextField
              label="备注（可选）"
              value={codeForm.note}
              onChange={(e) => setCodeForm({ ...codeForm, note: e.target.value })}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCodeDialog(false)} disabled={busy}>
            取消
          </Button>
          <Button variant="contained" onClick={submitCode} disabled={busy}>
            {busy ? "生成中…" : "生成"}
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

function EmptyState({
  message,
  actionLabel,
  onAction,
}: {
  message: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <Box sx={{ minHeight: 320, display: "grid", placeItems: "center", p: 4 }}>
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
