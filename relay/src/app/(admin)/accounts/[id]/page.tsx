"use client";
import * as React from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Banner, Button, Card, CardContent, CardHeader, CardTitle, Chip, Dialog, Icon, IconButton, TextField, useSnackbar } from "@/components/m3";
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

  async function refresh() {
    const res = await fetch(`/api/admin/accounts/${params.id}`);
    if (res.ok) setData(await res.json());
  }
  React.useEffect(() => { refresh(); }, [params.id]);

  if (!data) {
    return (
      <AdminShell title="Account"><div className="p-6 text-on-surface-variant">加载中…</div></AdminShell>
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
    <AdminShell
      title={account.displayName ?? account.accountID.slice(0, 8)}
      breadcrumb={["Billing", "Accounts"]}
      actions={<IconButton icon="arrow_back" onClick={() => router.back()} aria-label="返回" />}
    >
      <div className="mx-auto max-w-6xl space-y-4 p-6 pb-24">
        <Card variant="elevated">
          <CardContent className="flex flex-wrap items-center gap-4 p-5">
            <span className="flex h-14 w-14 items-center justify-center rounded-full bg-primary-container text-on-primary-container">
              <Icon name="account_circle" size={32} />
            </span>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <h2 className="truncate text-m3-headline-s">{account.displayName ?? "(未命名)"}</h2>
                <Badge tone={account.state === "active" ? "success" : account.state === "paused" ? "warn" : "error"}>
                  {account.state}
                </Badge>
                <Badge tone="info">{account.source}</Badge>
              </div>
              <div className="mt-1 font-mono text-m3-label-s text-on-surface-variant">{account.accountID}</div>
              {account.adminNote && <div className="mt-1 text-m3-body-s text-on-surface-variant">备注：{account.adminNote}</div>}
            </div>
            <Button variant="outlined" icon="edit" onClick={() => setEditAccount(true)}>编辑账户</Button>
          </CardContent>
        </Card>

        <div className="grid gap-4 md:grid-cols-3">
          <Card className="p-4"><div className="text-m3-label-m text-on-surface-variant">可用额度</div><div className="mt-1 text-m3-headline-s">{remaining.toLocaleString()}</div></Card>
          <Card className="p-4"><div className="text-m3-label-m text-on-surface-variant">最近到期</div><div className="mt-1 text-m3-title-m">{upcoming ? new Date(upcoming).toLocaleDateString() : "—"}</div></Card>
          <Card className="p-4"><div className="text-m3-label-m text-on-surface-variant">最近使用</div><div className="mt-1 text-m3-title-m">{account.lastUsageAt ? new Date(account.lastUsageAt).toLocaleString() : "—"}</div></Card>
        </div>

        <Card>
          <CardHeader><CardTitle>设备（{devices.length}）</CardTitle></CardHeader>
          <CardContent className="p-0">
            {devices.length === 0 ? (
              <div className="p-6 text-center text-on-surface-variant">此账户暂无设备</div>
            ) : (
              <table className="w-full text-left text-m3-body-s">
                <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
                  <tr>
                    <th className="px-3 py-2">平台</th>
                    <th className="px-3 py-2">别名 / ID</th>
                    <th className="px-3 py-2">最近</th>
                    <th className="px-3 py-2 w-32"></th>
                  </tr>
                </thead>
                <tbody>
                  {devices.map((d) => (
                    <tr key={d.deviceID} className="border-t border-outline-variant">
                      <td className="px-3 py-2"><Icon name={d.platform === "watch" ? "watch" : d.platform === "iPhone" ? "phone_iphone" : "computer"} size={18} /> {d.platform}</td>
                      <td className="px-3 py-2">
                        <div>{d.alias ?? "(未命名)"}</div>
                        <div className="font-mono text-m3-label-s text-on-surface-variant">{d.deviceID}</div>
                      </td>
                      <td className="px-3 py-2">{d.lastSeenAt ? new Date(d.lastSeenAt).toLocaleString() : "—"}</td>
                      <td className="px-3 py-2 text-right">
                        <IconButton icon="edit" size="sm" onClick={() => setEditDevice(d)} aria-label="改名" />
                        <IconButton icon="link_off" size="sm" onClick={() => unbindDevice(d.deviceID)} aria-label="解绑" />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Keys（{keys.length}）</CardTitle></CardHeader>
          <CardContent className="p-0">
            <KeyTable keys={keys} onEdit={setEditKey} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Grants（{grants.length}）</CardTitle></CardHeader>
          <CardContent className="p-0">
            <GrantTable grants={grants} onEdit={setEditGrant} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>最近用量（{usage.length}）</CardTitle></CardHeader>
          <CardContent className="p-0">
            <UsageTable usage={usage.slice(-50).reverse()} />
          </CardContent>
        </Card>
      </div>

      {editAccount && (
        <AccountEditDialog account={account} onClose={() => setEditAccount(false)} onDone={() => { setEditAccount(false); refresh(); }} />
      )}
      {editDevice && (
        <DeviceEditDialog device={editDevice} onClose={() => setEditDevice(null)} onDone={() => { setEditDevice(null); refresh(); }} />
      )}
      {editKey && (
        <KeyEditDialog keyRow={editKey} onClose={() => setEditKey(null)} onDone={() => { setEditKey(null); refresh(); }} />
      )}
      {editGrant && (
        <GrantEditDialog grant={editGrant} onClose={() => setEditGrant(null)} onDone={() => { setEditGrant(null); refresh(); }} />
      )}
    </AdminShell>
  );
}

function KeyTable({ keys, onEdit }: { keys: Key[]; onEdit: (k: Key) => void }) {
  const [reveal, setReveal] = React.useState(false);
  if (keys.length === 0) return <div className="p-6 text-center text-on-surface-variant">没有 Key</div>;
  return (
    <>
      <div className="flex justify-end p-2">
        <Chip selected={reveal} onClick={() => setReveal((v) => !v)} icon="visibility">
          {reveal ? "隐藏" : "显示"}明文
        </Chip>
      </div>
      <table className="w-full text-left text-m3-body-s">
        <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
          <tr>
            <th className="px-3 py-2">Key</th>
            <th className="px-3 py-2">状态</th>
            <th className="px-3 py-2">来源</th>
            <th className="px-3 py-2">备注</th>
            <th className="px-3 py-2 w-10"></th>
          </tr>
        </thead>
        <tbody>
          {keys.map((k) => (
            <tr key={k.keyID} className="border-t border-outline-variant">
              <td className="px-3 py-2 font-mono">{reveal ? k.keyValue : `${k.keyValue.slice(0, 8)}••••`}</td>
              <td className="px-3 py-2"><Badge tone={k.state === "active" ? "success" : k.state === "paused" ? "warn" : "error"}>{k.state}</Badge></td>
              <td className="px-3 py-2">{k.source}</td>
              <td className="px-3 py-2 text-on-surface-variant">{k.note ?? "—"}</td>
              <td className="px-3 py-2"><IconButton icon="edit" size="sm" onClick={() => onEdit(k)} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

function GrantTable({ grants, onEdit }: { grants: Grant[]; onEdit: (g: Grant) => void }) {
  if (grants.length === 0) return <div className="p-6 text-center text-on-surface-variant">没有 Grant</div>;
  return (
    <table className="w-full text-left text-m3-body-s">
      <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
        <tr>
          <th className="px-3 py-2">来源</th>
          <th className="px-3 py-2">余额</th>
          <th className="px-3 py-2">总量</th>
          <th className="px-3 py-2">到期</th>
          <th className="px-3 py-2">备注</th>
          <th className="px-3 py-2 w-10"></th>
        </tr>
      </thead>
      <tbody>
        {grants.map((g) => (
          <tr key={g.grantID} className="border-t border-outline-variant">
            <td className="px-3 py-2">{g.source}</td>
            <td className="px-3 py-2">{g.remainingCredits.toLocaleString()}</td>
            <td className="px-3 py-2 text-on-surface-variant">{g.totalCredits.toLocaleString()}</td>
            <td className="px-3 py-2">{g.expiresAt ? new Date(g.expiresAt).toLocaleDateString() : "—"}</td>
            <td className="px-3 py-2 text-on-surface-variant">{g.note ?? "—"}</td>
            <td className="px-3 py-2"><IconButton icon="tune" size="sm" onClick={() => onEdit(g)} aria-label="调整" /></td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function UsageTable({ usage }: { usage: UsageRecord[] }) {
  if (usage.length === 0) return <div className="p-6 text-center text-on-surface-variant">暂无用量</div>;
  return (
    <table className="w-full text-left text-m3-body-s">
      <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
        <tr>
          <th className="px-3 py-2">时间</th>
          <th className="px-3 py-2">端点</th>
          <th className="px-3 py-2">模型</th>
          <th className="px-3 py-2">Tokens</th>
          <th className="px-3 py-2">Credits</th>
        </tr>
      </thead>
      <tbody>
        {usage.map((u) => (
          <tr key={u.requestID} className="border-t border-outline-variant">
            <td className="px-3 py-2 text-on-surface-variant">{new Date(u.createdAt).toLocaleString()}</td>
            <td className="px-3 py-2 font-mono">{u.endpoint}</td>
            <td className="px-3 py-2">{u.modelID ?? "—"}</td>
            <td className="px-3 py-2">{u.inputTokens}→{u.outputTokens}</td>
            <td className="px-3 py-2">{u.settledCredits || u.reservedCredits}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function AccountEditDialog({ account, onClose, onDone }: { account: Account; onClose: () => void; onDone: () => void }) {
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
    <Dialog open onClose={onClose} title="编辑账户" actions={
      <>
        <Button variant="text" onClick={onClose}>取消</Button>
        <Button onClick={submit} loading={busy}>保存</Button>
      </>
    }>
      <div className="space-y-3">
        <TextField label="显示名称" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
        <TextField label="管理员备注" value={adminNote} onChange={(e) => setAdminNote(e.target.value)} />
        <div>
          <div className="text-m3-label-m text-on-surface-variant">状态</div>
          <div className="mt-1 flex gap-2">
            {(["active", "paused", "expired", "inactive"] as const).map((s) => (
              <Chip key={s} selected={state === s} onClick={() => setState(s)}>{s}</Chip>
            ))}
          </div>
        </div>
      </div>
    </Dialog>
  );
}

function DeviceEditDialog({ device, onClose, onDone }: { device: Device; onClose: () => void; onDone: () => void }) {
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
    <Dialog open onClose={onClose} title="编辑设备" actions={
      <>
        <Button variant="text" onClick={onClose}>取消</Button>
        <Button onClick={submit} loading={busy}>保存</Button>
      </>
    }>
      <div className="space-y-3">
        <TextField label="别名" value={alias} onChange={(e) => setAlias(e.target.value)} />
        <TextField label="备注" value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Dialog>
  );
}

function KeyEditDialog({ keyRow, onClose, onDone }: { keyRow: Key; onClose: () => void; onDone: () => void }) {
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
    <Dialog open onClose={onClose} title="编辑 Key" actions={
      <>
        <Button variant="text" onClick={onClose}>取消</Button>
        <Button onClick={submit} loading={busy}>保存</Button>
      </>
    }>
      <div className="space-y-3">
        <div>
          <div className="text-m3-label-m text-on-surface-variant">状态</div>
          <div className="mt-1 flex gap-2">
            {(["active", "paused", "revoked"] as const).map((s) => (
              <Chip key={s} selected={state === s} onClick={() => setState(s)}>{s}</Chip>
            ))}
          </div>
        </div>
        {state === "revoked" && <Banner tone="warn">吊销后客户端无法再用这把 key 调任何 v1 端点</Banner>}
        <TextField label="备注" value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Dialog>
  );
}

function GrantEditDialog({ grant, onClose, onDone }: { grant: Grant; onClose: () => void; onDone: () => void }) {
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
    <Dialog open onClose={onClose} title="调整 Grant" actions={
      <>
        <Button variant="text" onClick={onClose}>取消</Button>
        <Button onClick={submit} loading={busy}>保存</Button>
      </>
    }>
      <div className="space-y-3">
        <TextField label="余额" type="number" value={remainingCredits} onChange={(e) => setRemaining(Number(e.target.value) || 0)} />
        <TextField label="到期（YYYY-MM-DD）" value={expiresAt} onChange={(e) => setExpires(e.target.value)} supporting="留空表示永久" />
        <TextField label="备注" value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Dialog>
  );
}
