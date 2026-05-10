"use client";
import * as React from "react";
import Link from "next/link";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Chip from "@mui/material/Chip";
import TextField from "@mui/material/TextField";
import InputAdornment from "@mui/material/InputAdornment";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import MuiLink from "@mui/material/Link";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import { DataGrid, type GridColDef } from "@mui/x-data-grid";
import SearchIcon from "@mui/icons-material/Search";
import AddIcon from "@mui/icons-material/Add";
import AddCardIcon from "@mui/icons-material/AddCard";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import LinkOffIcon from "@mui/icons-material/LinkOff";
import BlockIcon from "@mui/icons-material/Block";
import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import WatchIcon from "@mui/icons-material/Watch";
import PhoneIphoneIcon from "@mui/icons-material/PhoneIphone";
import ComputerIcon from "@mui/icons-material/Computer";
import { AppShell } from "@/components/shell/app-shell";
import { useSnackbar } from "@/components/snackbar-provider";
import type { Account, Device, Key, ActivationCode, PairingToken } from "@/lib/billing/types";

interface BillingData {
  accounts: Account[];
  devices: Device[];
  keys: Key[];
  activationCodes: ActivationCode[];
  pairingTokens: PairingToken[];
}

type TabKey = "accounts" | "devices" | "keys" | "codes" | "pairing";

export default function AccountsPage() {
  const snack = useSnackbar();
  const [tab, setTab] = React.useState<TabKey>("accounts");
  const [data, setData] = React.useState<BillingData | null>(null);
  const [query, setQuery] = React.useState("");
  const [grantAccount, setGrantAccount] = React.useState<Account | null>(null);
  const [codeDialog, setCodeDialog] = React.useState(false);

  const refresh = React.useCallback(async () => {
    const res = await fetch("/api/admin/billing");
    setData(await res.json());
  }, []);

  React.useEffect(() => {
    refresh();
  }, [refresh]);

  const q = query.toLowerCase();
  const accounts = (data?.accounts ?? []).filter(
    (a) => !q || a.accountID.includes(q) || (a.displayName ?? "").toLowerCase().includes(q),
  );
  const devices = (data?.devices ?? []).filter(
    (d) => !q || d.deviceID.toLowerCase().includes(q) || (d.alias ?? "").toLowerCase().includes(q),
  );
  const keys = (data?.keys ?? []).filter(
    (k) => !q || k.keyValue.toLowerCase().includes(q) || (k.note ?? "").toLowerCase().includes(q),
  );
  const codes = (data?.activationCodes ?? []).filter((c) => !q || c.code.toLowerCase().includes(q));

  async function revokeCode(code: string) {
    if (!confirm(`吊销激活码 ${code}？`)) return;
    await fetch(`/api/admin/billing/activation-codes/${encodeURIComponent(code)}`, { method: "DELETE" });
    snack.push({ message: "激活码已吊销" });
    refresh();
  }
  async function revokeToken(token: string) {
    if (!confirm("吊销配对码？")) return;
    await fetch(`/api/admin/billing/pairing/${encodeURIComponent(token)}`, { method: "DELETE" });
    snack.push({ message: "配对码已吊销" });
    refresh();
  }
  async function unbindDevice(id: string) {
    if (!confirm("解绑设备会同时吊销其 key。继续？")) return;
    await fetch(`/api/admin/billing/device?id=${encodeURIComponent(id)}`, { method: "DELETE" });
    snack.push({ message: "设备已解绑" });
    refresh();
  }

  return (
    <AppShell title="Accounts" breadcrumb={["Billing"]}>
      <Box sx={{ p: 3 }}>
        <Stack spacing={2}>
          <Tabs value={tab} onChange={(_, v) => setTab(v as TabKey)} variant="scrollable" scrollButtons="auto">
            <Tab value="accounts" label={`账户 (${data?.accounts.length ?? 0})`} />
            <Tab value="devices" label={`设备 (${data?.devices.length ?? 0})`} />
            <Tab value="keys" label={`Keys (${data?.keys.length ?? 0})`} />
            <Tab value="codes" label={`激活码 (${data?.activationCodes.length ?? 0})`} />
            <Tab value="pairing" label={`配对 (${data?.pairingTokens.length ?? 0})`} />
          </Tabs>
          <Stack direction="row" spacing={2} alignItems="center">
            <Box sx={{ flex: 1, maxWidth: 480 }}>
              <TextField
                size="small"
                placeholder="搜索"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                InputProps={{
                  startAdornment: (
                    <InputAdornment position="start">
                      <SearchIcon fontSize="small" color="action" />
                    </InputAdornment>
                  ),
                }}
              />
            </Box>
            {tab === "codes" && (
              <Button startIcon={<AddIcon />} onClick={() => setCodeDialog(true)}>
                生成激活码
              </Button>
            )}
          </Stack>

          <Card>
            {tab === "accounts" && <AccountTable accounts={accounts} onGrant={setGrantAccount} />}
            {tab === "devices" && <DeviceTable devices={devices} onUnbind={unbindDevice} />}
            {tab === "keys" && <KeyTable keys={keys} />}
            {tab === "codes" && <CodeTable codes={codes} onRevoke={revokeCode} />}
            {tab === "pairing" && (
              <PairingTable tokens={data?.pairingTokens ?? []} onRevoke={revokeToken} />
            )}
          </Card>
        </Stack>
      </Box>

      {grantAccount && (
        <GrantDialog
          account={grantAccount}
          onClose={() => setGrantAccount(null)}
          onDone={() => {
            setGrantAccount(null);
            refresh();
            snack.push({ message: "额度已发放" });
          }}
        />
      )}
      {codeDialog && (
        <ActivationCodeDialog
          onClose={() => setCodeDialog(false)}
          onDone={() => {
            setCodeDialog(false);
            refresh();
            snack.push({ message: "激活码已生成" });
          }}
        />
      )}
    </AppShell>
  );
}

function AccountTable({
  accounts,
  onGrant,
}: {
  accounts: Account[];
  onGrant: (a: Account) => void;
}) {
  const columns: GridColDef<Account>[] = [
    {
      field: "displayName",
      headerName: "名称",
      flex: 1,
      minWidth: 220,
      renderCell: (params) => (
        <Box>
          <MuiLink component={Link} href={`/accounts/${params.row.accountID}`} underline="hover" variant="body2">
            {params.row.displayName ?? params.row.accountID.slice(0, 8)}
          </MuiLink>
          <Typography
            variant="caption"
            sx={{ display: "block", fontFamily: "monospace", color: "text.secondary" }}
          >
            {params.row.accountID}
          </Typography>
        </Box>
      ),
    },
    {
      field: "state",
      headerName: "状态",
      width: 110,
      renderCell: (params) => (
        <Chip
          size="small"
          color={
            params.row.state === "active"
              ? "success"
              : params.row.state === "paused"
                ? "warning"
                : "error"
          }
          label={params.row.state}
        />
      ),
    },
    { field: "source", headerName: "来源", width: 130 },
    {
      field: "creditBalance",
      headerName: "余额",
      width: 110,
      valueFormatter: (v: number) => v.toLocaleString(),
    },
    {
      field: "creditExpiresAt",
      headerName: "到期",
      width: 130,
      valueFormatter: (v: string | undefined) => (v ? new Date(v).toLocaleDateString() : "—"),
    },
    {
      field: "lastUsageAt",
      headerName: "最近使用",
      width: 180,
      valueFormatter: (v: string | undefined) => (v ? new Date(v).toLocaleString() : "—"),
    },
    {
      field: "_actions",
      headerName: "",
      width: 120,
      sortable: false,
      renderCell: (params) => (
        <Stack direction="row" spacing={0.5}>
          <Tooltip title="发额度">
            <IconButton size="small" onClick={() => onGrant(params.row)}>
              <AddCardIcon fontSize="small" />
            </IconButton>
          </Tooltip>
          <Tooltip title="详情">
            <IconButton size="small" component={Link} href={`/accounts/${params.row.accountID}`}>
              <ArrowForwardIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        </Stack>
      ),
    },
  ];
  return (
    <Box sx={{ height: 600 }}>
      <DataGrid
        rows={accounts}
        columns={columns}
        getRowId={(r) => r.accountID}
        density="compact"
        pageSizeOptions={[25, 50, 100]}
        initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
        localeText={{ noRowsLabel: "没有账户" }}
        disableRowSelectionOnClick
      />
    </Box>
  );
}

function DeviceTable({ devices, onUnbind }: { devices: Device[]; onUnbind: (id: string) => void }) {
  const columns: GridColDef<Device>[] = [
    {
      field: "alias",
      headerName: "设备",
      flex: 1,
      minWidth: 220,
      renderCell: (params) => (
        <Box>
          <Typography variant="body2" fontWeight={500}>
            {params.row.alias ?? params.row.deviceID.slice(0, 10)}
          </Typography>
          <Typography
            variant="caption"
            sx={{ display: "block", fontFamily: "monospace", color: "text.secondary" }}
          >
            {params.row.deviceID}
          </Typography>
        </Box>
      ),
    },
    {
      field: "platform",
      headerName: "平台",
      width: 140,
      renderCell: (params) => {
        const Icon =
          params.row.platform === "watch"
            ? WatchIcon
            : params.row.platform === "iPhone"
              ? PhoneIphoneIcon
              : ComputerIcon;
        return (
          <Stack direction="row" spacing={0.5} alignItems="center" sx={{ height: "100%" }}>
            <Icon fontSize="small" />
            <Typography variant="body2">{params.row.platform}</Typography>
          </Stack>
        );
      },
    },
    {
      field: "accountID",
      headerName: "账户",
      width: 140,
      renderCell: (params) => (
        <MuiLink
          component={Link}
          href={`/accounts/${params.row.accountID}`}
          underline="hover"
          sx={{ fontFamily: "monospace", fontSize: "0.75rem" }}
        >
          {params.row.accountID.slice(0, 8)}
        </MuiLink>
      ),
    },
    {
      field: "keyID",
      headerName: "Key",
      width: 120,
      valueFormatter: (v: string | undefined) => v?.slice(0, 8) ?? "—",
    },
    {
      field: "lastSeenAt",
      headerName: "最近",
      width: 180,
      valueFormatter: (v: string | undefined) => (v ? new Date(v).toLocaleString() : "—"),
    },
    {
      field: "_actions",
      headerName: "",
      width: 60,
      sortable: false,
      renderCell: (params) => (
        <Tooltip title="解绑">
          <IconButton size="small" onClick={() => onUnbind(params.row.deviceID)}>
            <LinkOffIcon fontSize="small" />
          </IconButton>
        </Tooltip>
      ),
    },
  ];
  return (
    <Box sx={{ height: 600 }}>
      <DataGrid
        rows={devices}
        columns={columns}
        getRowId={(r) => r.deviceID}
        density="compact"
        pageSizeOptions={[25, 50, 100]}
        initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
        localeText={{ noRowsLabel: "没有设备" }}
        disableRowSelectionOnClick
      />
    </Box>
  );
}

function KeyTable({ keys }: { keys: Key[] }) {
  const [reveal, setReveal] = React.useState(false);
  const columns: GridColDef<Key>[] = [
    {
      field: "keyValue",
      headerName: "Key",
      flex: 1,
      minWidth: 260,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontFamily: "monospace" }}>
          {reveal ? params.row.keyValue : `${params.row.keyValue.slice(0, 8)}••••`}
        </Typography>
      ),
    },
    {
      field: "accountID",
      headerName: "账户",
      width: 140,
      renderCell: (params) => (
        <MuiLink
          component={Link}
          href={`/accounts/${params.row.accountID}`}
          underline="hover"
          sx={{ fontFamily: "monospace", fontSize: "0.75rem" }}
        >
          {params.row.accountID.slice(0, 8)}
        </MuiLink>
      ),
    },
    {
      field: "state",
      headerName: "状态",
      width: 110,
      renderCell: (params) => (
        <Chip
          size="small"
          color={
            params.row.state === "active"
              ? "success"
              : params.row.state === "paused"
                ? "warning"
                : "error"
          }
          label={params.row.state}
        />
      ),
    },
    { field: "source", headerName: "来源", width: 140 },
    {
      field: "issuedAt",
      headerName: "发放时间",
      width: 140,
      valueFormatter: (v: string) => new Date(v).toLocaleDateString(),
    },
  ];
  return (
    <>
      <Box sx={{ display: "flex", justifyContent: "flex-end", p: 1.5 }}>
        <Chip
          icon={reveal ? <VisibilityOffIcon /> : <VisibilityIcon />}
          label={`${reveal ? "隐藏" : "显示"}明文`}
          color={reveal ? "primary" : "default"}
          variant={reveal ? "filled" : "outlined"}
          onClick={() => setReveal((v) => !v)}
        />
      </Box>
      <Box sx={{ height: 540 }}>
        <DataGrid
          rows={keys}
          columns={columns}
          getRowId={(r) => r.keyID}
          density="compact"
          pageSizeOptions={[25, 50, 100]}
          initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
          localeText={{ noRowsLabel: "没有 Key" }}
          disableRowSelectionOnClick
        />
      </Box>
    </>
  );
}

function CodeTable({
  codes,
  onRevoke,
}: {
  codes: ActivationCode[];
  onRevoke: (code: string) => void;
}) {
  const columns: GridColDef<ActivationCode>[] = [
    {
      field: "code",
      headerName: "激活码",
      flex: 1,
      minWidth: 240,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontFamily: "monospace" }}>
          {params.row.code}
        </Typography>
      ),
    },
    { field: "plan", headerName: "Plan", width: 140, valueFormatter: (v: string | undefined) => v ?? "—" },
    {
      field: "credits",
      headerName: "Credits",
      width: 110,
      valueFormatter: (v: number) => v.toLocaleString(),
    },
    {
      field: "expiresAt",
      headerName: "到期",
      width: 130,
      valueFormatter: (v: string | undefined) => (v ? new Date(v).toLocaleDateString() : "—"),
    },
    {
      field: "state",
      headerName: "状态",
      width: 110,
      renderCell: (params) => (
        <Chip
          size="small"
          color={
            params.row.state === "unused"
              ? "info"
              : params.row.state === "redeemed"
                ? "success"
                : "error"
          }
          label={params.row.state}
        />
      ),
    },
    {
      field: "note",
      headerName: "备注",
      flex: 1,
      minWidth: 160,
      valueFormatter: (v: string | undefined) => v ?? "—",
    },
    {
      field: "_actions",
      headerName: "",
      width: 60,
      sortable: false,
      renderCell: (params) =>
        params.row.state === "unused" ? (
          <Tooltip title="吊销">
            <IconButton size="small" onClick={() => onRevoke(params.row.code)}>
              <BlockIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        ) : null,
    },
  ];
  return (
    <Box sx={{ height: 600 }}>
      <DataGrid
        rows={codes}
        columns={columns}
        getRowId={(r) => r.code}
        density="compact"
        pageSizeOptions={[25, 50, 100]}
        initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
        localeText={{ noRowsLabel: "没有激活码" }}
        disableRowSelectionOnClick
      />
    </Box>
  );
}

function PairingTable({
  tokens,
  onRevoke,
}: {
  tokens: PairingToken[];
  onRevoke: (token: string) => void;
}) {
  const columns: GridColDef<PairingToken>[] = [
    {
      field: "token",
      headerName: "Token",
      flex: 1,
      minWidth: 240,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontFamily: "monospace" }}>
          {params.row.token}
        </Typography>
      ),
    },
    {
      field: "accountID",
      headerName: "账户",
      width: 140,
      valueFormatter: (v: string) => v.slice(0, 8),
    },
    {
      field: "issuedBy",
      headerName: "发起设备",
      width: 160,
      valueFormatter: (v: string) => v.slice(0, 10),
    },
    {
      field: "expiresAt",
      headerName: "过期",
      width: 180,
      valueFormatter: (v: string) => new Date(v).toLocaleString(),
    },
    {
      field: "_actions",
      headerName: "",
      width: 60,
      sortable: false,
      renderCell: (params) => (
        <Tooltip title="吊销">
          <IconButton size="small" onClick={() => onRevoke(params.row.token)}>
            <BlockIcon fontSize="small" />
          </IconButton>
        </Tooltip>
      ),
    },
  ];
  return (
    <Box sx={{ height: 600 }}>
      <DataGrid
        rows={tokens}
        columns={columns}
        getRowId={(r) => r.token}
        density="compact"
        pageSizeOptions={[25, 50, 100]}
        initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
        localeText={{ noRowsLabel: "没有配对码" }}
        disableRowSelectionOnClick
      />
    </Box>
  );
}

function GrantDialog({
  account,
  onClose,
  onDone,
}: {
  account: Account;
  onClose: () => void;
  onDone: () => void;
}) {
  const [credits, setCredits] = React.useState(1000);
  const [source, setSource] = React.useState<"subscription" | "trial" | "offlineManual">("subscription");
  const [note, setNote] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  async function submit() {
    setBusy(true);
    await fetch("/api/admin/billing/grant", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ accountID: account.accountID, credits, source, note }),
    });
    setBusy(false);
    onDone();
  }
  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>发放额度</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <Typography variant="body2">
            账户：{account.displayName ?? account.accountID}
          </Typography>
          <TextField
            label="Credits"
            type="number"
            value={credits}
            onChange={(e) => setCredits(Number(e.target.value) || 0)}
          />
          <Box>
            <Typography variant="caption" sx={{ color: "text.secondary" }}>
              来源
            </Typography>
            <Stack direction="row" spacing={1} sx={{ mt: 0.5 }}>
              {(["subscription", "trial", "offlineManual"] as const).map((s) => (
                <Chip
                  key={s}
                  label={s}
                  color={source === s ? "primary" : "default"}
                  variant={source === s ? "filled" : "outlined"}
                  onClick={() => setSource(s)}
                />
              ))}
            </Stack>
          </Box>
          <TextField
            label="备注（可选）"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button variant="text" onClick={onClose}>
          取消
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "处理中…" : "发放"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function ActivationCodeDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [count, setCount] = React.useState(10);
  const [credits, setCredits] = React.useState(10000);
  const [plan, setPlan] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  async function submit() {
    setBusy(true);
    await fetch("/api/admin/billing/activation-codes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ count, credits, plan: plan || undefined }),
    });
    setBusy(false);
    onDone();
  }
  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>批量生成激活码</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <TextField
            label="数量"
            type="number"
            value={count}
            onChange={(e) => setCount(Number(e.target.value) || 0)}
          />
          <TextField
            label="每个 credits"
            type="number"
            value={credits}
            onChange={(e) => setCredits(Number(e.target.value) || 0)}
          />
          <TextField
            label="Plan ID（可选）"
            value={plan}
            onChange={(e) => setPlan(e.target.value)}
          />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button variant="text" onClick={onClose}>
          取消
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "处理中…" : "生成"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
