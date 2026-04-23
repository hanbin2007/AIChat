"use client";
import * as React from "react";
import { useRouter } from "next/navigation";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Card, CardContent, CardHeader, CardTitle, Chip, Segmented, TextField, Icon, IconButton } from "@/components/m3";
import type { ActivityEntry } from "@/lib/store/request-log";
import type { Conversation } from "@/lib/store/conversations";
import { cn } from "@/lib/cn";

type View = "live" | "history" | "conversations";
type Level = "info" | "success" | "warning" | "error";

export default function RequestsPage() {
  const router = useRouter();
  const [view, setView] = React.useState<View>("history");
  const [paused, setPaused] = React.useState(false);
  const [query, setQuery] = React.useState("");
  const [levels, setLevels] = React.useState<Record<Level, boolean>>({
    info: true,
    success: true,
    warning: true,
    error: true,
  });
  const [hasErrorsOnly, setHasErrorsOnly] = React.useState(false);
  const [entries, setEntries] = React.useState<ActivityEntry[]>([]);
  const [conversations, setConversations] = React.useState<Conversation[]>([]);
  const [selected, setSelected] = React.useState<ActivityEntry | null>(null);

  React.useEffect(() => {
    if (view !== "conversations") {
      fetch("/api/admin/requests").then((r) => r.json()).then((d) => setEntries(d.requests));
    }
  }, [view]);

  React.useEffect(() => {
    if (view === "conversations") {
      const params = new URLSearchParams();
      if (hasErrorsOnly) params.set("hasErrors", "1");
      if (query) params.set("q", query);
      fetch(`/api/admin/conversations?${params}`).then((r) => r.json()).then((d) => setConversations(d.conversations));
    }
  }, [view, hasErrorsOnly, query]);

  React.useEffect(() => {
    if (view !== "live" || paused) return;
    const es = new EventSource("/api/admin/requests/stream");
    es.addEventListener("activity", (evt) => {
      try {
        const entry = JSON.parse((evt as MessageEvent).data) as ActivityEntry;
        setEntries((prev) => [entry, ...prev].slice(0, 500));
      } catch { /* ignore */ }
    });
    return () => es.close();
  }, [view, paused]);

  const filtered = entries.filter((e) => {
    if (!levels[e.level]) return false;
    if (hasErrorsOnly && e.level !== "error") return false;
    if (query) {
      const q = query.toLowerCase();
      if (
        !e.message.toLowerCase().includes(q) &&
        !e.path?.toLowerCase().includes(q) &&
        !e.modelID?.toLowerCase().includes(q) &&
        !e.accountID?.toLowerCase().includes(q)
      ) {
        return false;
      }
    }
    return true;
  });

  return (
    <AdminShell
      title="Requests"
      breadcrumb={["Relay"]}
      actions={
        view === "live" && (
          <IconButton
            icon={paused ? "play_arrow" : "pause"}
            onClick={() => setPaused((p) => !p)}
            aria-label={paused ? "恢复" : "暂停"}
          />
        )
      }
    >
      <div className="space-y-4 p-6">
        <div className="flex flex-wrap items-center gap-3">
          <Segmented
            value={view}
            onChange={setView}
            options={[
              { value: "live", label: "Live", icon: "bolt" },
              { value: "history", label: "History", icon: "history" },
              { value: "conversations", label: "Conversations", icon: "chat" },
            ]}
          />
          <div className="flex-1 min-w-64 max-w-md">
            <TextField
              leading="search"
              placeholder="搜索路径 / 模型 / 账户 / 消息"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              variant="filled"
            />
          </div>
        </div>

        {view !== "conversations" && (
          <div className="flex flex-wrap gap-2">
            {(["info", "success", "warning", "error"] as Level[]).map((lvl) => (
              <Chip
                key={lvl}
                selected={levels[lvl]}
                onClick={() => setLevels((p) => ({ ...p, [lvl]: !p[lvl] }))}
              >
                {lvl}
              </Chip>
            ))}
            <Chip selected={hasErrorsOnly} onClick={() => setHasErrorsOnly((v) => !v)}>
              仅错误
            </Chip>
          </div>
        )}

        {view === "conversations" ? (
          <ConversationList conversations={conversations} onOpen={(id) => router.push(`/requests/conversations/${id}`)} />
        ) : (
          <Card>
            <CardContent className="p-0">
              <div className="overflow-hidden rounded-m3-md">
                <table className="w-full text-left text-m3-body-s">
                  <thead className="bg-surface-container-low text-m3-label-m text-on-surface-variant">
                    <tr>
                      <th className="px-3 py-2">时间</th>
                      <th className="px-3 py-2">端点</th>
                      <th className="px-3 py-2">状态</th>
                      <th className="px-3 py-2">延迟</th>
                      <th className="px-3 py-2">Tokens</th>
                      <th className="px-3 py-2">模型</th>
                      <th className="px-3 py-2">设备</th>
                      <th className="px-3 py-2">Credits</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.length === 0 && (
                      <tr>
                        <td colSpan={8} className="px-3 py-8 text-center text-on-surface-variant">
                          没有匹配的请求
                        </td>
                      </tr>
                    )}
                    {filtered.map((e) => (
                      <tr
                        key={e.id}
                        onClick={() => setSelected(e)}
                        className="cursor-pointer border-t border-outline-variant hover:bg-surface-container-low"
                      >
                        <td className="px-3 py-2 text-on-surface-variant">
                          {new Date(e.timestamp).toLocaleTimeString()}
                        </td>
                        <td className="px-3 py-2 font-mono">{e.path ?? "—"}</td>
                        <td className="px-3 py-2">
                          <Badge tone={e.level === "error" ? "error" : e.level === "warning" ? "warn" : "success"}>
                            {e.statusCode ?? e.level}
                          </Badge>
                        </td>
                        <td className="px-3 py-2">{e.latencyMs ?? 0}ms</td>
                        <td className="px-3 py-2">
                          {(e.inputTokens ?? 0).toLocaleString()} / {(e.outputTokens ?? 0).toLocaleString()}
                        </td>
                        <td className="px-3 py-2">{e.modelID ?? "—"}</td>
                        <td className="px-3 py-2">{e.deviceID?.slice(0, 10) ?? "—"}</td>
                        <td className="px-3 py-2">{e.settledCredits ?? e.reservedCredits ?? "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
      {selected && <DetailDrawer entry={selected} onClose={() => setSelected(null)} />}
    </AdminShell>
  );
}

function ConversationList({
  conversations,
  onOpen,
}: {
  conversations: Conversation[];
  onOpen: (id: string) => void;
}) {
  if (conversations.length === 0) {
    return (
      <Card className="p-8 text-center text-on-surface-variant">
        <Icon name="chat" size={36} className="opacity-50" />
        <div className="mt-3">还没有可重建的会话</div>
        <div className="text-m3-body-s">客户端发送第一次 /v1/chat/stream 后，这里就会出现</div>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="p-0">
        <ul className="divide-y divide-outline-variant">
          {conversations.map((c) => (
            <li key={c.id}>
              <button
                onClick={() => onOpen(c.id)}
                className="state-layer flex w-full items-start gap-3 px-4 py-4 text-left"
              >
                <span className="mt-1 flex h-10 w-10 items-center justify-center rounded-full bg-primary-container text-on-primary-container">
                  <Icon name={c.devicePlatform === "watch" ? "watch" : c.devicePlatform === "iPhone" ? "phone_iphone" : "computer"} size={22} />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <h3 className="truncate text-m3-title-s">{c.title}</h3>
                    {c.confidence === "low" && (
                      <span
                        title="推断归属"
                        className="h-2 w-2 rounded-full bg-on-surface-variant"
                      />
                    )}
                    {c.hasErrors && <Badge tone="error">has errors</Badge>}
                    {c.hasImages && <Badge tone="info">images</Badge>}
                    {c.hasAudio && <Badge tone="info">audio</Badge>}
                  </div>
                  <div className="mt-1 flex flex-wrap items-center gap-2 text-m3-body-s text-on-surface-variant">
                    <span>{c.accountID?.slice(0, 8) ?? "—"}</span>
                    <span>·</span>
                    <span>{c.turnCount} turns</span>
                    <span>·</span>
                    <span>{c.modelsUsed.join(", ")}</span>
                    <span>·</span>
                    <span>{formatNumber(c.totalCredits)} credits</span>
                  </div>
                </div>
                <span className="ml-auto shrink-0 text-m3-body-s text-on-surface-variant">
                  {relativeTime(c.lastAt)}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

function DetailDrawer({ entry, onClose }: { entry: ActivityEntry; onClose: () => void }) {
  const [tab, setTab] = React.useState<"request" | "response" | "stream">("request");
  return (
    <div className="fixed inset-0 z-40 flex justify-end bg-scrim/40" onClick={onClose}>
      <div
        className="h-full w-full max-w-lg overflow-y-auto bg-surface-container-low shadow-2xl thin-scroll"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sticky top-0 flex items-center gap-3 border-b border-outline-variant bg-surface-container p-4">
          <IconButton icon="close" onClick={onClose} />
          <div className="flex-1 min-w-0">
            <div className="truncate text-m3-title-s">{entry.message}</div>
            <div className="text-m3-body-s text-on-surface-variant">
              {entry.method} {entry.path} · {entry.statusCode}
            </div>
          </div>
        </div>
        <div className="flex gap-1 border-b border-outline-variant px-2">
          {(["request", "response", "stream"] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn(
                "state-layer rounded-t-m3-xs px-4 py-2 text-m3-label-l",
                tab === t ? "text-primary" : "text-on-surface-variant",
              )}
            >
              {t}
            </button>
          ))}
        </div>
        <div className="p-4">
          {tab === "request" && (
            <div className="space-y-3">
              <InfoRow label="requestId" value={entry.id} />
              <InfoRow label="timestamp" value={entry.timestamp} />
              <InfoRow label="remote" value={entry.remoteAddress ?? "—"} />
              <InfoRow label="account" value={entry.accountID ?? "—"} />
              <InfoRow label="device" value={entry.deviceID ?? "—"} />
              <InfoRow label="model" value={entry.modelID ?? "—"} />
              <CodeBlock content={JSON.stringify(entry.requestBody ?? null, null, 2)} />
            </div>
          )}
          {tab === "response" && (
            <div className="space-y-3">
              <InfoRow label="status" value={String(entry.statusCode ?? "—")} />
              <InfoRow label="finishReason" value={entry.finishReason ?? "—"} />
              <InfoRow label="latency" value={`${entry.latencyMs ?? 0}ms`} />
              <InfoRow label="tokens" value={`${entry.inputTokens ?? 0} / ${entry.outputTokens ?? 0}`} />
              <InfoRow label="credits" value={`${entry.reservedCredits ?? 0} → ${entry.settledCredits ?? 0}`} />
              {entry.responseSummary && (
                <div>
                  <div className="text-m3-label-m text-on-surface-variant">response preview</div>
                  <div className="mt-1 rounded-m3-sm bg-surface-container-high p-3 text-m3-body-m">
                    {entry.responseSummary}
                  </div>
                </div>
              )}
            </div>
          )}
          {tab === "stream" && (
            <div className="space-y-2">
              {(entry.events ?? []).length === 0 ? (
                <div className="text-m3-body-m text-on-surface-variant">没有捕获流事件</div>
              ) : (
                (entry.events ?? []).map((ev, i) => (
                  <div key={i} className="rounded-m3-sm border border-outline-variant p-3">
                    <div className="text-m3-label-m text-on-surface-variant">{ev.type} · {ev.at}</div>
                    <pre className="mt-1 whitespace-pre-wrap break-all font-mono text-m3-body-s text-on-surface">{truncate(JSON.stringify(ev.data), 600)}</pre>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4 border-b border-outline-variant py-2 text-m3-body-s">
      <span className="text-on-surface-variant">{label}</span>
      <span className="truncate text-right font-mono">{value}</span>
    </div>
  );
}

function CodeBlock({ content }: { content: string }) {
  return (
    <pre className="rounded-m3-sm bg-surface-container-high p-3 font-mono text-m3-body-s thin-scroll overflow-auto max-h-96">{content}</pre>
  );
}

function relativeTime(iso: string): string {
  const age = Date.now() - new Date(iso).getTime();
  if (age < 60_000) return `${Math.floor(age / 1000)}s ago`;
  if (age < 3600_000) return `${Math.floor(age / 60_000)}m ago`;
  if (age < 86400_000) return `${Math.floor(age / 3600_000)}h ago`;
  return new Date(iso).toLocaleDateString();
}

function formatNumber(n: number): string {
  if (n > 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n > 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toLocaleString();
}

function truncate(s: string, max: number): string {
  return s.length > max ? `${s.slice(0, max)}…` : s;
}
