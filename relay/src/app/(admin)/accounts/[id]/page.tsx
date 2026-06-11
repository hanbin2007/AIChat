import Link from "next/link";
import { notFound } from "next/navigation";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
import Avatar from "@mui/material/Avatar";
import Table from "@mui/material/Table";
import TableHead from "@mui/material/TableHead";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import IconButton from "@mui/material/IconButton";
import ArrowBackRounded from "@mui/icons-material/ArrowBackRounded";
import { billingStore } from "@/lib/store/billing-store";
import type { Account, Device, Key, Grant, UsageRecord } from "@/lib/billing/types";

export const dynamic = "force-dynamic";

export default async function AccountDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const billing = await billingStore().listAll();
  const account = billing.accounts.find((a) => a.accountID === id);
  if (!account) notFound();

  const devices: Device[] = billing.devices.filter((d) => d.accountID === id);
  const keys: Key[] = billing.keys.filter((k) => k.accountID === id);
  const grants: Grant[] = billing.grants.filter((g) => g.accountID === id);
  const usage: UsageRecord[] = billing.usage
    .filter((u) => u.accountID === id)
    .slice(-50)
    .reverse();

  const remaining = grants.reduce((s, g) => s + g.remainingCredits, 0);
  const nextExpiry = grants
    .filter((g) => g.expiresAt)
    .map((g) => g.expiresAt!)
    .sort()[0];

  return (
    <>
      <Stack spacing={3}>
        <Card>
          <CardContent>
            <Stack direction={{ xs: "column", md: "row" }} spacing={2} alignItems="flex-start">
              <Avatar sx={{ bgcolor: "primary.main", width: 56, height: 56 }}>
                {(account.displayName ?? "A").charAt(0).toUpperCase()}
              </Avatar>
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {account.displayName ?? "（未命名）"}
                  </Typography>
                  <Chip size="small" label={account.state} />
                  <Chip size="small" label={account.source} variant="outlined" />
                </Stack>
                <Typography
                  variant="caption"
                  color="text.secondary"
                  sx={{ fontFamily: "var(--font-mono)", display: "block" }}
                >
                  {account.accountID}
                </Typography>
                {account.adminNote ? (
                  <Typography
                    variant="body2"
                    color="text.secondary"
                    sx={{ mt: 1, fontStyle: "italic" }}
                  >
                    {account.adminNote}
                  </Typography>
                ) : null}
              </Box>
            </Stack>
          </CardContent>
        </Card>

        <Box
          sx={{
            display: "grid",
            gridTemplateColumns: { xs: "1fr", md: "repeat(3, 1fr)" },
            gap: 2,
          }}
        >
          <KpiSummary label="可用额度" value={`${remaining}`} helper={`授信 ${grants.length} 项`} />
          <KpiSummary
            label="最近到期"
            value={nextExpiry ? new Date(nextExpiry).toLocaleDateString("zh-Hans") : "—"}
          />
          <KpiSummary
            label="最近使用"
            value={
              account.lastUsageAt ? new Date(account.lastUsageAt).toLocaleString("zh-Hans") : "—"
            }
          />
        </Box>

        <Section title={`设备 (${devices.length})`}>
          {devices.length === 0 ? (
            <Empty>该账户暂未绑定任何设备</Empty>
          ) : (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>平台</TableCell>
                  <TableCell>名称</TableCell>
                  <TableCell>设备 ID</TableCell>
                  <TableCell>最近上线</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {devices.map((d) => (
                  <TableRow key={d.deviceID}>
                    <TableCell>{d.platform}</TableCell>
                    <TableCell>{d.alias ?? "—"}</TableCell>
                    <TableCell sx={{ fontFamily: "var(--font-mono)" }}>{d.deviceID}</TableCell>
                    <TableCell>
                      {d.lastSeenAt ? new Date(d.lastSeenAt).toLocaleString("zh-Hans") : "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Section>

        <Section title={`Keys (${keys.length})`}>
          {keys.length === 0 ? (
            <Empty>暂无 Key</Empty>
          ) : (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Key</TableCell>
                  <TableCell>状态</TableCell>
                  <TableCell>来源</TableCell>
                  <TableCell>签发于</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {keys.map((k) => (
                  <TableRow key={k.keyID}>
                    <TableCell sx={{ fontFamily: "var(--font-mono)" }}>
                      {k.keyValue.slice(0, 12)}…
                    </TableCell>
                    <TableCell>
                      <Chip size="small" label={k.state} />
                    </TableCell>
                    <TableCell>{k.source}</TableCell>
                    <TableCell>{new Date(k.issuedAt).toLocaleString("zh-Hans")}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Section>

        <Section title={`授信 (${grants.length})`}>
          {grants.length === 0 ? (
            <Empty>无授信记录</Empty>
          ) : (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>来源</TableCell>
                  <TableCell align="right">总额</TableCell>
                  <TableCell align="right">剩余</TableCell>
                  <TableCell>授予时间</TableCell>
                  <TableCell>到期</TableCell>
                  <TableCell>备注</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {grants.map((g) => (
                  <TableRow key={g.grantID}>
                    <TableCell>{g.source}</TableCell>
                    <TableCell align="right" sx={{ fontFamily: "var(--font-mono)" }}>
                      {g.totalCredits}
                    </TableCell>
                    <TableCell align="right" sx={{ fontFamily: "var(--font-mono)" }}>
                      {g.remainingCredits}
                    </TableCell>
                    <TableCell>{new Date(g.grantedAt).toLocaleString("zh-Hans")}</TableCell>
                    <TableCell>
                      {g.expiresAt ? new Date(g.expiresAt).toLocaleDateString("zh-Hans") : "—"}
                    </TableCell>
                    <TableCell>{g.note ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Section>

        <Section title={`最近用量 (${usage.length})`}>
          {usage.length === 0 ? (
            <Empty>无用量数据</Empty>
          ) : (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>时间</TableCell>
                  <TableCell>端点</TableCell>
                  <TableCell>模型</TableCell>
                  <TableCell align="right">Tokens</TableCell>
                  <TableCell align="right">Credits</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {usage.map((u) => (
                  <TableRow key={u.requestID}>
                    <TableCell sx={{ color: "text.secondary" }}>
                      {new Date(u.createdAt).toLocaleString("zh-Hans")}
                    </TableCell>
                    <TableCell sx={{ fontFamily: "var(--font-mono)" }}>{u.endpoint}</TableCell>
                    <TableCell sx={{ fontFamily: "var(--font-mono)" }}>{u.modelID ?? "—"}</TableCell>
                    <TableCell align="right" sx={{ fontFamily: "var(--font-mono)" }}>
                      {u.inputTokens} → {u.outputTokens}
                    </TableCell>
                    <TableCell align="right" sx={{ fontFamily: "var(--font-mono)" }}>
                      {u.settledCredits || u.reservedCredits}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Section>
      </Stack>
    </>
  );
}

function KpiSummary({ label, value, helper }: { label: string; value: string; helper?: string }) {
  return (
    <Card>
      <CardContent>
        <Typography variant="overline" color="text.secondary">
          {label}
        </Typography>
        <Typography variant="h5" sx={{ fontFamily: "var(--font-mono)", fontWeight: 700, mt: 0.5 }}>
          {value}
        </Typography>
        {helper ? (
          <Typography variant="caption" color="text.secondary">
            {helper}
          </Typography>
        ) : null}
      </CardContent>
    </Card>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardHeader title={title} />
      <CardContent sx={{ p: 0, "&:last-child": { pb: 0 } }}>{children}</CardContent>
    </Card>
  );
}

function Empty({ children }: { children: React.ReactNode }) {
  return (
    <Box sx={{ p: 3, textAlign: "center" }}>
      <Typography variant="body2" color="text.secondary">
        {children}
      </Typography>
    </Box>
  );
}
