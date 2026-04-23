"use client";
import * as React from "react";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Card, CardContent, Chip, Tabs, Icon, IconButton, TextField, Button, Dialog, useSnackbar } from "@/components/m3";
import type { Account, Device, Key, ActivationCode, PairingToken } from "@/lib/billing/types";

interface BillingData {
  accounts: Account[];
  devices: Device[];
  keys: Key[];
  activationCodes: ActivationCode[];
  pairingTokens: PairingToken[];
}

type Tab = "accounts" | "devices" | "keys" | "codes" | "pairing";

export default function AccountsPage() {
  const snack = useSnackbar();
  const [tab, setTab] = React.useState<Tab>("accounts");
  const [data, setData] = React.useState<BillingData | null>(null);
  const [query, setQuery] = React.useState("");
  const [grantAccount, setGrantAccount] = React.useState<Account | null>(null);
  const [codeDialog, setCodeDialog] = React.useState(false);

  async function refresh() {
    const res = await fetch("/api/admin/billing");
    setData(await res.json());
  }
  React.useEffect(() => { refresh(); }, []);

  const q = query.toLowerCase();
  const accounts = (data?.accounts ?? []).filter((a) =>
    !q || a.accountID.includes(q) || (a.displayName ?? "").toLowerCase().includes(q),
  );
  const devices = (data?.devices ?? []).filter((d) =>
    !q || d.deviceID.toLowerCase().includes(q) || (d.alias ?? "").toLowerCase().includes(q),
  );
  const keys = (data?.keys ?? []).filter((k) =>
    !q || k.keyValue.toLowerCase().includes(q) || (k.note ?? "").toLowerCase().includes(q),
  );
  const codes = (data?.activationCodes ?? []).filter((c) =>
    !q || c.code.toLowerCase().includes(q),
  );

  return (
    <AdminShell title="Accounts" breadcrumb={["Billing"]}>
      <div className="space-y-4 p-6">
        <Tabs
          value={tab}
          onChange={setTab}
          options={[
            { value: "accounts", label: `账户 (${data?.accounts.length ?? 0})` },
            { value: "devices", label: `设备 (${data?.devices.length ?? 0})` },
            { value: "keys", label: `Keys (${data?.keys.length ?? 0})` },
            { value: "codes", label: `激活码 (${data?.activationCodes.length ?? 0})` },
            { value: "pairing", label: `配对 (${data?.pairingTokens.length ?? 0})` },
          ]}
        />
        <div className="flex items-center gap-3">
          <div className="flex-1 max-w-md">
            <TextField leading="search" placeholder="搜索" value={query} onChange={(e) => setQuery(e.target.value)} variant="filled" />
          </div>
          {tab === "codes" && <Button icon="add" onClick={() => setCodeDialog(true)}>生成激活码</Button>}
        </div>

        <Card>
          <CardContent className="p-0">
            {tab === "accounts" && <AccountTable accounts={accounts} onGrant={setGrantAccount} />}
            {tab === "devices" && <DeviceTable devices={devices} />}
            {tab === "keys" && <KeyTable keys={keys} onChange={refresh} />}
            {tab === "codes" && <CodeTable codes={codes} />}
            {tab === "pairing" && <PairingTable tokens={data?.pairingTokens ?? []} />}
          </CardContent>
        </Card>
      </div>

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
    </AdminShell>
  );
}

function AccountTable({ accounts, onGrant }: { accounts: Account[]; onGrant: (a: Account) => void }) {
  return (
    <table className="w-full text-left text-m3-body-s">
      <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
        <tr>
          <th className="px-3 py-2">名称</th>
          <th className="px-3 py-2">状态</th>
          <th className="px-3 py-2">来源</th>
          <th className="px-3 py-2">余额</th>
          <th className="px-3 py-2">到期</th>
          <th className="px-3 py-2">最近使用</th>
          <th className="px-3 py-2 w-10"></th>
        </tr>
      </thead>
      <tbody>
        {accounts.map((a) => (
          <tr key={a.accountID} className="border-t border-outline-variant">
            <td className="px-3 py-2">
              <div className="font-medium">{a.displayName ?? a.accountID.slice(0, 8)}</div>
              <div className="font-mono text-m3-label-s text-on-surface-variant">{a.accountID}</div>
            </td>
            <td className="px-3 py-2">
              <Badge tone={a.state === "active" ? "success" : a.state === "paused" ? "warn" : "error"}>
                {a.state}
              </Badge>
            </td>
            <td className="px-3 py-2">{a.source}</td>
            <td className="px-3 py-2">{a.creditBalance.toLocaleString()}</td>
            <td className="px-3 py-2">{a.creditExpiresAt ? new Date(a.creditExpiresAt).toLocaleDateString() : "—"}</td>
            <td className="px-3 py-2">{a.lastUsageAt ? new Date(a.lastUsageAt).toLocaleString() : "—"}</td>
            <td className="px-3 py-2">
              <IconButton icon="add_card" size="sm" onClick={() => onGrant(a)} aria-label="发额度" />
            </td>
          </tr>
        ))}
        {accounts.length === 0 && (
          <tr><td colSpan={7} className="px-3 py-8 text-center text-on-surface-variant">没有账户</td></tr>
        )}
      </tbody>
    </table>
  );
}

function DeviceTable({ devices }: { devices: Device[] }) {
  return (
    <table className="w-full text-left text-m3-body-s">
      <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
        <tr>
          <th className="px-3 py-2">设备</th>
          <th className="px-3 py-2">平台</th>
          <th className="px-3 py-2">账户</th>
          <th className="px-3 py-2">Key</th>
          <th className="px-3 py-2">最近</th>
        </tr>
      </thead>
      <tbody>
        {devices.map((d) => (
          <tr key={d.deviceID} className="border-t border-outline-variant">
            <td className="px-3 py-2">
              <div className="font-medium">{d.alias ?? d.deviceID.slice(0, 10)}</div>
              <div className="font-mono text-m3-label-s text-on-surface-variant">{d.deviceID}</div>
            </td>
            <td className="px-3 py-2">
              <span className="inline-flex items-center gap-1">
                <Icon name={d.platform === "watch" ? "watch" : d.platform === "iPhone" ? "phone_iphone" : "computer"} size={18} />
                {d.platform}
              </span>
            </td>
            <td className="px-3 py-2 font-mono text-m3-label-s">{d.accountID.slice(0, 8)}</td>
            <td className="px-3 py-2 font-mono text-m3-label-s">{d.keyID?.slice(0, 8) ?? "—"}</td>
            <td className="px-3 py-2">{d.lastSeenAt ? new Date(d.lastSeenAt).toLocaleString() : "—"}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function KeyTable({ keys, onChange }: { keys: Key[]; onChange: () => void }) {
  const [reveal, setReveal] = React.useState(false);
  return (
    <>
      <div className="flex items-center justify-end gap-2 px-3 py-2">
        <Chip selected={reveal} onClick={() => setReveal((v) => !v)} icon="visibility">
          {reveal ? "隐藏" : "显示"}明文
        </Chip>
      </div>
      <table className="w-full text-left text-m3-body-s">
        <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
          <tr>
            <th className="px-3 py-2">Key</th>
            <th className="px-3 py-2">账户</th>
            <th className="px-3 py-2">设备</th>
            <th className="px-3 py-2">状态</th>
            <th className="px-3 py-2">来源</th>
            <th className="px-3 py-2">发放时间</th>
          </tr>
        </thead>
        <tbody>
          {keys.map((k) => (
            <tr key={k.keyID} className="border-t border-outline-variant">
              <td className="px-3 py-2 font-mono">{reveal ? k.keyValue : `${k.keyValue.slice(0, 8)}••••`}</td>
              <td className="px-3 py-2 font-mono text-m3-label-s">{k.accountID.slice(0, 8)}</td>
              <td className="px-3 py-2 font-mono text-m3-label-s">{k.deviceID?.slice(0, 10) ?? "—"}</td>
              <td className="px-3 py-2">
                <Badge tone={k.state === "active" ? "success" : k.state === "paused" ? "warn" : "error"}>
                  {k.state}
                </Badge>
              </td>
              <td className="px-3 py-2">{k.source}</td>
              <td className="px-3 py-2">{new Date(k.issuedAt).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

function CodeTable({ codes }: { codes: ActivationCode[] }) {
  return (
    <table className="w-full text-left text-m3-body-s">
      <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
        <tr>
          <th className="px-3 py-2">激活码</th>
          <th className="px-3 py-2">Plan</th>
          <th className="px-3 py-2">Credits</th>
          <th className="px-3 py-2">到期</th>
          <th className="px-3 py-2">状态</th>
          <th className="px-3 py-2">备注</th>
        </tr>
      </thead>
      <tbody>
        {codes.map((c) => (
          <tr key={c.code} className="border-t border-outline-variant">
            <td className="px-3 py-2 font-mono">{c.code}</td>
            <td className="px-3 py-2">{c.plan ?? "—"}</td>
            <td className="px-3 py-2">{c.credits.toLocaleString()}</td>
            <td className="px-3 py-2">{c.expiresAt ? new Date(c.expiresAt).toLocaleDateString() : "—"}</td>
            <td className="px-3 py-2">
              <Badge tone={c.state === "unused" ? "info" : c.state === "redeemed" ? "success" : "error"}>
                {c.state}
              </Badge>
            </td>
            <td className="px-3 py-2 text-on-surface-variant">{c.note ?? "—"}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function PairingTable({ tokens }: { tokens: PairingToken[] }) {
  return (
    <table className="w-full text-left text-m3-body-s">
      <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
        <tr>
          <th className="px-3 py-2">Token</th>
          <th className="px-3 py-2">账户</th>
          <th className="px-3 py-2">发起设备</th>
          <th className="px-3 py-2">过期</th>
        </tr>
      </thead>
      <tbody>
        {tokens.map((t) => (
          <tr key={t.token} className="border-t border-outline-variant">
            <td className="px-3 py-2 font-mono">{t.token}</td>
            <td className="px-3 py-2 font-mono text-m3-label-s">{t.accountID.slice(0, 8)}</td>
            <td className="px-3 py-2 font-mono text-m3-label-s">{t.issuedBy.slice(0, 10)}</td>
            <td className="px-3 py-2">{new Date(t.expiresAt).toLocaleString()}</td>
          </tr>
        ))}
      </tbody>
    </table>
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
    <Dialog
      open
      onClose={onClose}
      title="发放额度"
      actions={
        <>
          <Button variant="text" onClick={onClose}>取消</Button>
          <Button onClick={submit} loading={busy}>发放</Button>
        </>
      }
    >
      <div className="space-y-3">
        <div className="text-m3-body-s">账户：{account.displayName ?? account.accountID}</div>
        <TextField
          label="Credits"
          type="number"
          value={credits}
          onChange={(e) => setCredits(Number(e.target.value) || 0)}
        />
        <div>
          <div className="text-m3-label-m text-on-surface-variant">来源</div>
          <div className="mt-1 flex gap-2">
            {(["subscription", "trial", "offlineManual"] as const).map((s) => (
              <Chip key={s} selected={source === s} onClick={() => setSource(s)}>
                {s}
              </Chip>
            ))}
          </div>
        </div>
        <TextField label="备注（可选）" value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Dialog>
  );
}

function ActivationCodeDialog({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: () => void;
}) {
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
    <Dialog
      open
      onClose={onClose}
      title="批量生成激活码"
      actions={
        <>
          <Button variant="text" onClick={onClose}>取消</Button>
          <Button onClick={submit} loading={busy}>生成</Button>
        </>
      }
    >
      <div className="space-y-3">
        <TextField label="数量" type="number" value={count} onChange={(e) => setCount(Number(e.target.value) || 0)} />
        <TextField label="每个 credits" type="number" value={credits} onChange={(e) => setCredits(Number(e.target.value) || 0)} />
        <TextField label="Plan ID（可选）" value={plan} onChange={(e) => setPlan(e.target.value)} />
      </div>
    </Dialog>
  );
}
