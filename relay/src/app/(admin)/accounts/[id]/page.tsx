"use client";
import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import Avatar from "@mui/material/Avatar";
import Chip from "@mui/material/Chip";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Grid from "@mui/material/Grid2";
import TextField from "@mui/material/TextField";
import Alert from "@mui/material/Alert";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import TableContainer from "@mui/material/TableContainer";
import AccountCircleIcon from "@mui/icons-material/AccountCircle";
import EditIcon from "@mui/icons-material/Edit";
import LinkOffIcon from "@mui/icons-material/LinkOff";
import TuneIcon from "@mui/icons-material/Tune";
import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import WatchIcon from "@mui/icons-material/Watch";
import PhoneIphoneIcon from "@mui/icons-material/PhoneIphone";
import ComputerIcon from "@mui/icons-material/Computer";
import { AppShell } from "@/components/shell/app-shell";
import { useSnackbar } from "@/components/snackbar-provider";
import type { Account, Device, Grant, Key, UsageRecord } from "@/lib/billing/types";

interface AccountDetail {
  account: Account;
  devices: Device[];
  keys: Key[];
  grants: Grant[];
  usage: UsageRecord[];
}

export default function AccountDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const snack = useSnackbar();
  const [data, setData] = React.useState<AccountDetail | null>(null);
  const [editAccount, setEditAccount] = React.useState(false);
  const [editDevice, setEditDevice] = React.useState<Device | null>(null);
  const [editKey, setEditKey] = React.useState<Key | null>(null);
  const [editGrant, setEditGrant] = React.useState<Grant | null>(null);

  const refresh = React.useCallback(async () => {
    const res = await fetch(`/api/admin/accounts/${params.id}`);
    if (res.ok) setData(await res.json());
  }, [params.id]);

  React.useEffect(() => {
    refresh();
  }, [refresh]);

  if (!data) {
    return (
      <AppShell title="Account">
        <Box sx={{ p: 3, color: "text.secondary" }}>加载中…</Box>
      </AppShell>
    );
  }
  const { account, devices, keys, grants, usage } = data;
  const remaining = grants.reduce((s, g) => s + g.remainingCredits, 0);
  const upcoming = grants
    .filter((g) => g.expiresAt)
    .map((g) => g.expiresAt!)
    .sort()[0];

  async function unbindDevice(deviceID: string) {
    if (!confirm("解绑设备会吊销其 key。继续？")) return;
    await fetch(`/api/admin/billing/device?id=${encodeURIComponent(deviceID)}`, { method: "DELETE" });
    snack.push({ message: "设备已解绑" });
    refresh();
  }

  return (
    <AppShell
      title={account.displayName ?? account.accountID.slice(0, 8)}
      breadcrumb={["Billing", "Accounts"]}
      actions={
        <Tooltip title="返回">
          <IconButton onClick={() => router.back()} aria-label="返回">
            <ArrowBackIcon />
          </IconButton>
        </Tooltip>
      }
    >
      <Box sx={{ maxWidth: 1280, mx: "auto", p: 3, pb: 12 }}>
        <Stack spacing={2}>
          <Card sx={{ boxShadow: 1 }}>
            <CardContent>
              <Stack direction="row" spacing={2} alignItems="center" flexWrap="wrap" useFlexGap>
                <Avatar sx={{ width: 56, height: 56, bgcolor: "primary.main" }}>
                  <AccountCircleIcon sx={{ fontSize: 32 }} />
                </Avatar>
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
                    <Typography variant="h5" noWrap>
                      {account.displayName ?? "(未命名)"}
                    </Typography>
                    <Chip
                      size="small"
                      color={
                        account.state === "active"
                          ? "success"
                          : account.state === "paused"
                            ? "warning"
                            : "error"
                      }
                      label={account.state}
                    />
                    <Chip size="small" color="info" label={account.source} />
                  </Stack>
                  <Typography
                    variant="caption"
                    sx={{ display: "block", fontFamily: "monospace", color: "text.secondary", mt: 0.5 }}
                  >
                    {account.accountID}
                  </Typography>
                  {account.adminNote && (
                    <Typography variant="caption" sx={{ color: "text.secondary", display: "block", mt: 0.5 }}>
                      备注：{account.adminNote}
                    </Typography>
                  )}
                </Box>
                <Button variant="outlined" startIcon={<EditIcon />} onClick={() => setEditAccount(true)}>
                  编辑账户
                </Button>
              </Stack>
            </CardContent>
          </Card>

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, md: 4 }}>
              <Card>
                <CardContent>
                  <Typography variant="caption" sx={{ color: "text.secondary" }}>
                    可用额度
                  </Typography>
                  <Typography variant="h5" sx={{ mt: 0.5 }}>
                    {remaining.toLocaleString()}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
            <Grid size={{ xs: 12, md: 4 }}>
              <Card>
                <CardContent>
                  <Typography variant="caption" sx={{ color: "text.secondary" }}>
                    最近到期
                  </Typography>
                  <Typography variant="subtitle1" sx={{ mt: 0.5 }}>
                    {upcoming ? new Date(upcoming).toLocaleDateString() : "—"}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
            <Grid size={{ xs: 12, md: 4 }}>
              <Card>
                <CardContent>
                  <Typography variant="caption" sx={{ color: "text.secondary" }}>
                    最近使用
                  </Typography>
                  <Typography variant="subtitle1" sx={{ mt: 0.5 }}>
                    {account.lastUsageAt ? new Date(account.lastUsageAt).toLocaleString() : "—"}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
          </Grid>

          <Card>
            <CardHeader title={`设备（${devices.length}）`} titleTypographyProps={{ variant: "subtitle1" }} />
            {devices.length === 0 ? (
              <Box sx={{ p: 3, textAlign: "center", color: "text.secondary" }}>此账户暂无设备</Box>
            ) : (
              <TableContainer>
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell>平台</TableCell>
                      <TableCell>别名 / ID</TableCell>
                      <TableCell>最近</TableCell>
                      <TableCell align="right" sx={{ width: 120 }} />
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {devices.map((d) => {
                      const Icon =
                        d.platform === "watch"
                          ? WatchIcon
                          : d.platform === "iPhone"
                            ? PhoneIphoneIcon
                            : ComputerIcon;
                      return (
                        <TableRow key={d.deviceID} hover>
                          <TableCell>
                            <Stack direction="row" spacing={0.5} alignItems="center">
                              <Icon fontSize="small" />
                              <span>{d.platform}</span>
                            </Stack>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2">{d.alias ?? "(未命名)"}</Typography>
                            <Typography
                              variant="caption"
                              sx={{ fontFamily: "monospace", color: "text.secondary" }}
                            >
                              {d.deviceID}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            {d.lastSeenAt ? new Date(d.lastSeenAt).toLocaleString() : "—"}
                          </TableCell>
                          <TableCell align="right">
                            <Tooltip title="改名">
                              <IconButton size="small" onClick={() => setEditDevice(d)}>
                                <EditIcon fontSize="small" />
                              </IconButton>
                            </Tooltip>
                            <Tooltip title="解绑">
                              <IconButton size="small" onClick={() => unbindDevice(d.deviceID)}>
                                <LinkOffIcon fontSize="small" />
                              </IconButton>
                            </Tooltip>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </Card>

          <Card>
            <CardHeader title={`Keys（${keys.length}）`} titleTypographyProps={{ variant: "subtitle1" }} />
            <KeyTable keys={keys} onEdit={setEditKey} />
          </Card>

          <Card>
            <CardHeader title={`Grants（${grants.length}）`} titleTypographyProps={{ variant: "subtitle1" }} />
            <GrantTable grants={grants} onEdit={setEditGrant} />
          </Card>

          <Card>
            <CardHeader
              title={`最近用量（${usage.length}）`}
              titleTypographyProps={{ variant: "subtitle1" }}
            />
            <UsageTable usage={usage.slice(-50).reverse()} />
          </Card>
        </Stack>
      </Box>

      {editAccount && (
        <AccountEditDialog
          account={account}
          onClose={() => setEditAccount(false)}
          onDone={() => {
            setEditAccount(false);
            refresh();
          }}
        />
      )}
      {editDevice && (
        <DeviceEditDialog
          device={editDevice}
          onClose={() => setEditDevice(null)}
          onDone={() => {
            setEditDevice(null);
            refresh();
          }}
        />
      )}
      {editKey && (
        <KeyEditDialog
          keyRow={editKey}
          onClose={() => setEditKey(null)}
          onDone={() => {
            setEditKey(null);
            refresh();
          }}
        />
      )}
      {editGrant && (
        <GrantEditDialog
          grant={editGrant}
          onClose={() => setEditGrant(null)}
          onDone={() => {
            setEditGrant(null);
            refresh();
          }}
        />
      )}
    </AppShell>
  );
}

function KeyTable({ keys, onEdit }: { keys: Key[]; onEdit: (k: Key) => void }) {
  const [reveal, setReveal] = React.useState(false);
  if (keys.length === 0)
    return <Box sx={{ p: 3, textAlign: "center", color: "text.secondary" }}>没有 Key</Box>;
  return (
    <>
      <Box sx={{ display: "flex", justifyContent: "flex-end", p: 1 }}>
        <Chip
          icon={reveal ? <VisibilityOffIcon /> : <VisibilityIcon />}
          label={`${reveal ? "隐藏" : "显示"}明文`}
          color={reveal ? "primary" : "default"}
          variant={reveal ? "filled" : "outlined"}
          onClick={() => setReveal((v) => !v)}
          size="small"
        />
      </Box>
      <TableContainer>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell>Key</TableCell>
              <TableCell>状态</TableCell>
              <TableCell>来源</TableCell>
              <TableCell>备注</TableCell>
              <TableCell align="right" sx={{ width: 60 }} />
            </TableRow>
          </TableHead>
          <TableBody>
            {keys.map((k) => (
              <TableRow key={k.keyID} hover>
                <TableCell sx={{ fontFamily: "monospace" }}>
                  {reveal ? k.keyValue : `${k.keyValue.slice(0, 8)}••••`}
                </TableCell>
                <TableCell>
                  <Chip
                    size="small"
                    color={
                      k.state === "active" ? "success" : k.state === "paused" ? "warning" : "error"
                    }
                    label={k.state}
                  />
                </TableCell>
                <TableCell>{k.source}</TableCell>
                <TableCell sx={{ color: "text.secondary" }}>{k.note ?? "—"}</TableCell>
                <TableCell align="right">
                  <IconButton size="small" onClick={() => onEdit(k)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
    </>
  );
}

function GrantTable({ grants, onEdit }: { grants: Grant[]; onEdit: (g: Grant) => void }) {
  if (grants.length === 0)
    return <Box sx={{ p: 3, textAlign: "center", color: "text.secondary" }}>没有 Grant</Box>;
  return (
    <TableContainer>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>来源</TableCell>
            <TableCell>余额</TableCell>
            <TableCell>总量</TableCell>
            <TableCell>到期</TableCell>
            <TableCell>备注</TableCell>
            <TableCell align="right" sx={{ width: 60 }} />
          </TableRow>
        </TableHead>
        <TableBody>
          {grants.map((g) => (
            <TableRow key={g.grantID} hover>
              <TableCell>{g.source}</TableCell>
              <TableCell>{g.remainingCredits.toLocaleString()}</TableCell>
              <TableCell sx={{ color: "text.secondary" }}>
                {g.totalCredits.toLocaleString()}
              </TableCell>
              <TableCell>
                {g.expiresAt ? new Date(g.expiresAt).toLocaleDateString() : "—"}
              </TableCell>
              <TableCell sx={{ color: "text.secondary" }}>{g.note ?? "—"}</TableCell>
              <TableCell align="right">
                <Tooltip title="调整">
                  <IconButton size="small" onClick={() => onEdit(g)}>
                    <TuneIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
}

function UsageTable({ usage }: { usage: UsageRecord[] }) {
  if (usage.length === 0)
    return <Box sx={{ p: 3, textAlign: "center", color: "text.secondary" }}>暂无用量</Box>;
  return (
    <TableContainer>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>时间</TableCell>
            <TableCell>端点</TableCell>
            <TableCell>模型</TableCell>
            <TableCell>Tokens</TableCell>
            <TableCell>Credits</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {usage.map((u) => (
            <TableRow key={u.requestID} hover>
              <TableCell sx={{ color: "text.secondary" }}>
                {new Date(u.createdAt).toLocaleString()}
              </TableCell>
              <TableCell sx={{ fontFamily: "monospace" }}>{u.endpoint}</TableCell>
              <TableCell>{u.modelID ?? "—"}</TableCell>
              <TableCell>
                {u.inputTokens}→{u.outputTokens}
              </TableCell>
              <TableCell>{u.settledCredits || u.reservedCredits}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
}

function AccountEditDialog({
  account,
  onClose,
  onDone,
}: {
  account: Account;
  onClose: () => void;
  onDone: () => void;
}) {
  const [displayName, setDisplayName] = React.useState(account.displayName ?? "");
  const [adminNote, setAdminNote] = React.useState(account.adminNote ?? "");
  const [state, setState] = React.useState(account.state);
  const [busy, setBusy] = React.useState(false);
  async function submit() {
    setBusy(true);
    await fetch("/api/admin/billing/account", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ accountID: account.accountID, displayName, adminNote, state }),
    });
    setBusy(false);
    onDone();
  }
  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>编辑账户</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <TextField
            label="显示名称"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
          />
          <TextField
            label="管理员备注"
            value={adminNote}
            onChange={(e) => setAdminNote(e.target.value)}
          />
          <Box>
            <Typography variant="caption" sx={{ color: "text.secondary" }}>
              状态
            </Typography>
            <Stack direction="row" spacing={1} sx={{ mt: 0.5 }} flexWrap="wrap" useFlexGap>
              {(["active", "paused", "expired", "inactive"] as const).map((s) => (
                <Chip
                  key={s}
                  label={s}
                  color={state === s ? "primary" : "default"}
                  variant={state === s ? "filled" : "outlined"}
                  onClick={() => setState(s)}
                />
              ))}
            </Stack>
          </Box>
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button variant="text" onClick={onClose}>
          取消
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "处理中…" : "保存"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function DeviceEditDialog({
  device,
  onClose,
  onDone,
}: {
  device: Device;
  onClose: () => void;
  onDone: () => void;
}) {
  const [alias, setAlias] = React.useState(device.alias ?? "");
  const [note, setNote] = React.useState(device.note ?? "");
  const [busy, setBusy] = React.useState(false);
  async function submit() {
    setBusy(true);
    await fetch("/api/admin/billing/device", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ deviceID: device.deviceID, alias, note }),
    });
    setBusy(false);
    onDone();
  }
  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>编辑设备</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <TextField label="别名" value={alias} onChange={(e) => setAlias(e.target.value)} />
          <TextField label="备注" value={note} onChange={(e) => setNote(e.target.value)} />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button variant="text" onClick={onClose}>
          取消
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "处理中…" : "保存"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function KeyEditDialog({
  keyRow,
  onClose,
  onDone,
}: {
  keyRow: Key;
  onClose: () => void;
  onDone: () => void;
}) {
  const [state, setState] = React.useState(keyRow.state);
  const [note, setNote] = React.useState(keyRow.note ?? "");
  const [busy, setBusy] = React.useState(false);
  async function submit() {
    setBusy(true);
    await fetch("/api/admin/billing/key", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ keyID: keyRow.keyID, state, note }),
    });
    setBusy(false);
    onDone();
  }
  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>编辑 Key</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <Box>
            <Typography variant="caption" sx={{ color: "text.secondary" }}>
              状态
            </Typography>
            <Stack direction="row" spacing={1} sx={{ mt: 0.5 }}>
              {(["active", "paused", "revoked"] as const).map((s) => (
                <Chip
                  key={s}
                  label={s}
                  color={state === s ? "primary" : "default"}
                  variant={state === s ? "filled" : "outlined"}
                  onClick={() => setState(s)}
                />
              ))}
            </Stack>
          </Box>
          {state === "revoked" && (
            <Alert severity="warning">吊销后客户端无法再用这把 key 调任何 v1 端点</Alert>
          )}
          <TextField label="备注" value={note} onChange={(e) => setNote(e.target.value)} />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button variant="text" onClick={onClose}>
          取消
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "处理中…" : "保存"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function GrantEditDialog({
  grant,
  onClose,
  onDone,
}: {
  grant: Grant;
  onClose: () => void;
  onDone: () => void;
}) {
  const [remainingCredits, setRemaining] = React.useState(grant.remainingCredits);
  const [expiresAt, setExpires] = React.useState(grant.expiresAt?.slice(0, 10) ?? "");
  const [note, setNote] = React.useState(grant.note ?? "");
  const [busy, setBusy] = React.useState(false);
  async function submit() {
    setBusy(true);
    await fetch(`/api/admin/billing/grant/${grant.grantID}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        remainingCredits,
        expiresAt: expiresAt ? new Date(expiresAt).toISOString() : undefined,
        note,
      }),
    });
    setBusy(false);
    onDone();
  }
  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>调整 Grant</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <TextField
            label="余额"
            type="number"
            value={remainingCredits}
            onChange={(e) => setRemaining(Number(e.target.value) || 0)}
          />
          <TextField
            label="到期（YYYY-MM-DD）"
            value={expiresAt}
            onChange={(e) => setExpires(e.target.value)}
            helperText="留空表示永久"
          />
          <TextField label="备注" value={note} onChange={(e) => setNote(e.target.value)} />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button variant="text" onClick={onClose}>
          取消
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "处理中…" : "保存"}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
