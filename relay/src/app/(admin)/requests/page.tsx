"use client";
import * as React from "react";
import { useRouter } from "next/navigation";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import TextField from "@mui/material/TextField";
import InputAdornment from "@mui/material/InputAdornment";
import Chip from "@mui/material/Chip";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Drawer from "@mui/material/Drawer";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Avatar from "@mui/material/Avatar";
import Divider from "@mui/material/Divider";
import ToggleButton from "@mui/material/ToggleButton";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import { DataGrid, type GridColDef } from "@mui/x-data-grid";
import BoltIcon from "@mui/icons-material/Bolt";
import HistoryIcon from "@mui/icons-material/History";
import ChatIcon from "@mui/icons-material/Chat";
import SearchIcon from "@mui/icons-material/Search";
import PauseIcon from "@mui/icons-material/Pause";
import PlayArrowIcon from "@mui/icons-material/PlayArrow";
import CloseIcon from "@mui/icons-material/Close";
import WatchIcon from "@mui/icons-material/Watch";
import PhoneIphoneIcon from "@mui/icons-material/PhoneIphone";
import ComputerIcon from "@mui/icons-material/Computer";
import { AppShell } from "@/components/shell/app-shell";
import { Markdown } from "@/components/markdown";
import type { ActivityEntry } from "@/lib/store/request-log";
import type { Conversation } from "@/lib/store/conversations";

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
      fetch(`/api/admin/conversations?${params}`)
        .then((r) => r.json())
        .then((d) => setConversations(d.conversations));
    }
  }, [view, hasErrorsOnly, query]);

  React.useEffect(() => {
    if (view !== "live" || paused) return;
    const es = new EventSource("/api/admin/requests/stream");
    es.addEventListener("activity", (evt) => {
      try {
        const entry = JSON.parse((evt as MessageEvent).data) as ActivityEntry;
        setEntries((prev) => [entry, ...prev].slice(0, 500));
      } catch {
        /* ignore */
      }
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

  const columns: GridColDef<ActivityEntry>[] = [
    {
      field: "timestamp",
      headerName: "时间",
      width: 110,
      valueFormatter: (v: string) => new Date(v).toLocaleTimeString(),
    },
    {
      field: "path",
      headerName: "端点",
      width: 220,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontFamily: "monospace" }}>
          {params.row.path ?? "—"}
        </Typography>
      ),
    },
    {
      field: "statusCode",
      headerName: "状态",
      width: 100,
      renderCell: (params) => (
        <Chip
          size="small"
          color={
            params.row.level === "error"
              ? "error"
              : params.row.level === "warning"
                ? "warning"
                : "success"
          }
          label={params.row.statusCode ?? params.row.level}
        />
      ),
    },
    {
      field: "latencyMs",
      headerName: "延迟",
      width: 80,
      valueGetter: (_v, row) => `${row.latencyMs ?? 0}ms`,
    },
    {
      field: "tokens",
      headerName: "Tokens",
      width: 140,
      renderCell: (params) =>
        `${(params.row.inputTokens ?? 0).toLocaleString()} / ${(params.row.outputTokens ?? 0).toLocaleString()}`,
    },
    { field: "modelID", headerName: "模型", width: 180, valueGetter: (_v, row) => row.modelID ?? "—" },
    {
      field: "deviceID",
      headerName: "设备",
      width: 120,
      valueGetter: (_v, row) => row.deviceID?.slice(0, 10) ?? "—",
    },
    {
      field: "credits",
      headerName: "Credits",
      width: 100,
      valueGetter: (_v, row) => row.settledCredits ?? row.reservedCredits ?? "—",
    },
  ];

  return (
    <AppShell
      title="Requests"
      breadcrumb={["Relay"]}
      actions={
        view === "live" ? (
          <Tooltip title={paused ? "恢复" : "暂停"}>
            <IconButton onClick={() => setPaused((p) => !p)} aria-label={paused ? "恢复" : "暂停"}>
              {paused ? <PlayArrowIcon /> : <PauseIcon />}
            </IconButton>
          </Tooltip>
        ) : null
      }
    >
      <Box sx={{ p: 3 }}>
        <Stack spacing={2}>
          <Stack direction="row" spacing={2} flexWrap="wrap" useFlexGap alignItems="center">
            <ToggleButtonGroup
              size="small"
              exclusive
              value={view}
              onChange={(_, v) => v && setView(v as View)}
            >
              <ToggleButton value="live">
                <BoltIcon fontSize="small" sx={{ mr: 0.5 }} /> Live
              </ToggleButton>
              <ToggleButton value="history">
                <HistoryIcon fontSize="small" sx={{ mr: 0.5 }} /> History
              </ToggleButton>
              <ToggleButton value="conversations">
                <ChatIcon fontSize="small" sx={{ mr: 0.5 }} /> Conversations
              </ToggleButton>
            </ToggleButtonGroup>
            <Box sx={{ flex: 1, minWidth: 256, maxWidth: 480 }}>
              <TextField
                size="small"
                placeholder="搜索路径 / 模型 / 账户 / 消息"
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
          </Stack>

          {view !== "conversations" && (
            <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
              {(["info", "success", "warning", "error"] as Level[]).map((lvl) => (
                <Chip
                  key={lvl}
                  label={lvl}
                  color={levels[lvl] ? "primary" : "default"}
                  variant={levels[lvl] ? "filled" : "outlined"}
                  onClick={() => setLevels((p) => ({ ...p, [lvl]: !p[lvl] }))}
                />
              ))}
              <Chip
                label="仅错误"
                color={hasErrorsOnly ? "error" : "default"}
                variant={hasErrorsOnly ? "filled" : "outlined"}
                onClick={() => setHasErrorsOnly((v) => !v)}
              />
            </Stack>
          )}

          {view === "conversations" ? (
            <ConversationList
              conversations={conversations}
              onOpen={(id) => router.push(`/requests/conversations/${id}`)}
            />
          ) : (
            <Card>
              <Box sx={{ height: 640 }}>
                <DataGrid
                  rows={filtered}
                  columns={columns}
                  getRowId={(r) => r.id}
                  density="compact"
                  pageSizeOptions={[25, 50, 100]}
                  initialState={{ pagination: { paginationModel: { pageSize: 50 } } }}
                  onRowClick={(p) => setSelected(p.row as ActivityEntry)}
                  localeText={{ noRowsLabel: "没有匹配的请求" }}
                  disableRowSelectionOnClick
                  sx={{ "& .MuiDataGrid-row": { cursor: "pointer" } }}
                />
              </Box>
            </Card>
          )}
        </Stack>
      </Box>
      <DetailDrawer entry={selected} onClose={() => setSelected(null)} />
    </AppShell>
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
      <Card>
        <Stack alignItems="center" sx={{ py: 6, color: "text.secondary" }}>
          <ChatIcon sx={{ fontSize: 36, opacity: 0.5 }} />
          <Typography variant="body2" sx={{ mt: 1.5 }}>
            还没有可重建的会话
          </Typography>
          <Typography variant="caption">
            客户端发送第一次 /v1/chat/stream 后，这里就会出现
          </Typography>
        </Stack>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent sx={{ p: 0, "&:last-child": { pb: 0 } }}>
        <Stack divider={<Divider />}>
          {conversations.map((c) => {
            const PlatformIcon =
              c.devicePlatform === "watch"
                ? WatchIcon
                : c.devicePlatform === "iPhone"
                  ? PhoneIphoneIcon
                  : ComputerIcon;
            return (
              <Box
                key={c.id}
                component="button"
                onClick={() => onOpen(c.id)}
                sx={{
                  display: "flex",
                  alignItems: "flex-start",
                  gap: 1.5,
                  p: 2,
                  width: "100%",
                  border: 0,
                  bgcolor: "transparent",
                  textAlign: "left",
                  cursor: "pointer",
                  "&:hover": { bgcolor: "action.hover" },
                }}
              >
                <Avatar sx={{ bgcolor: "primary.main", color: "primary.contrastText" }}>
                  <PlatformIcon />
                </Avatar>
                <Box sx={{ minWidth: 0, flex: 1 }}>
                  <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
                    <Typography variant="subtitle2" noWrap sx={{ minWidth: 0 }}>
                      {c.title}
                    </Typography>
                    {c.confidence === "low" && (
                      <Tooltip title="推断归属">
                        <Box
                          sx={{
                            width: 8,
                            height: 8,
                            borderRadius: "50%",
                            bgcolor: "text.secondary",
                          }}
                        />
                      </Tooltip>
                    )}
                    {c.hasErrors && <Chip size="small" color="error" label="has errors" />}
                    {c.hasImages && <Chip size="small" color="info" label="images" />}
                    {c.hasAudio && <Chip size="small" color="info" label="audio" />}
                  </Stack>
                  <Typography variant="caption" sx={{ color: "text.secondary", display: "block", mt: 0.5 }}>
                    {c.accountID?.slice(0, 8) ?? "—"} · {c.turnCount} turns ·{" "}
                    {c.modelsUsed.join(", ")} · {formatNumber(c.totalCredits)} credits
                  </Typography>
                </Box>
                <Typography variant="caption" sx={{ color: "text.secondary", flexShrink: 0 }}>
                  {relativeTime(c.lastAt)}
                </Typography>
              </Box>
            );
          })}
        </Stack>
      </CardContent>
    </Card>
  );
}

function DetailDrawer({ entry, onClose }: { entry: ActivityEntry | null; onClose: () => void }) {
  const [tab, setTab] = React.useState<"request" | "response" | "stream">("request");
  return (
    <Drawer
      anchor="right"
      open={Boolean(entry)}
      onClose={onClose}
      PaperProps={{ sx: { width: { xs: "100%", sm: 520 } } }}
    >
      {entry && (
        <Box sx={{ height: "100%", display: "flex", flexDirection: "column" }}>
          <Box
            sx={{
              p: 2,
              display: "flex",
              alignItems: "center",
              gap: 1.5,
              borderBottom: 1,
              borderColor: "divider",
              bgcolor: "background.default",
            }}
          >
            <IconButton onClick={onClose} size="small">
              <CloseIcon />
            </IconButton>
            <Box sx={{ flex: 1, minWidth: 0 }}>
              <Typography variant="subtitle2" noWrap>
                {entry.message}
              </Typography>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                {entry.method} {entry.path} · {entry.statusCode}
              </Typography>
            </Box>
          </Box>
          <Tabs
            value={tab}
            onChange={(_, v) => setTab(v as typeof tab)}
            sx={{ borderBottom: 1, borderColor: "divider", px: 1 }}
          >
            <Tab value="request" label="request" />
            <Tab value="response" label="response" />
            <Tab value="stream" label="stream" />
          </Tabs>
          <Box sx={{ flex: 1, overflow: "auto", p: 2 }}>
            {tab === "request" && (
              <Stack spacing={1.5}>
                <InfoRow label="requestId" value={entry.id} />
                <InfoRow label="timestamp" value={entry.timestamp} />
                <InfoRow label="remote" value={entry.remoteAddress ?? "—"} />
                <InfoRow label="account" value={entry.accountID ?? "—"} />
                <InfoRow label="device" value={entry.deviceID ?? "—"} />
                <InfoRow label="model" value={entry.modelID ?? "—"} />
                <CodeBlock content={JSON.stringify(entry.requestBody ?? null, null, 2)} />
              </Stack>
            )}
            {tab === "response" && (
              <Stack spacing={1.5}>
                <InfoRow label="status" value={String(entry.statusCode ?? "—")} />
                <InfoRow label="finishReason" value={entry.finishReason ?? "—"} />
                <InfoRow label="latency" value={`${entry.latencyMs ?? 0}ms`} />
                <InfoRow
                  label="tokens"
                  value={`${entry.inputTokens ?? 0} / ${entry.outputTokens ?? 0}`}
                />
                <InfoRow
                  label="credits"
                  value={`${entry.reservedCredits ?? 0} → ${entry.settledCredits ?? 0}`}
                />
                {entry.responseSummary && (
                  <Box>
                    <Typography variant="caption" sx={{ color: "text.secondary" }}>
                      response preview
                    </Typography>
                    <Box
                      sx={{
                        mt: 0.5,
                        bgcolor: "action.hover",
                        borderRadius: 2,
                        p: 1.5,
                        fontSize: "0.875rem",
                      }}
                    >
                      <Markdown text={entry.responseSummary} />
                    </Box>
                  </Box>
                )}
              </Stack>
            )}
            {tab === "stream" && (
              <Stack spacing={1.5}>
                {(entry.events ?? []).length === 0 ? (
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    没有捕获流事件
                  </Typography>
                ) : (
                  (entry.events ?? []).map((ev, i) => (
                    <Box key={i} sx={{ border: 1, borderColor: "divider", borderRadius: 2, p: 1.5 }}>
                      <Typography variant="caption" sx={{ color: "text.secondary" }}>
                        {ev.type} · {ev.at}
                      </Typography>
                      <Box
                        component="pre"
                        sx={{
                          mt: 0.5,
                          whiteSpace: "pre-wrap",
                          wordBreak: "break-all",
                          fontFamily: "monospace",
                          fontSize: "0.75rem",
                        }}
                      >
                        {truncate(JSON.stringify(ev.data), 600)}
                      </Box>
                    </Box>
                  ))
                )}
              </Stack>
            )}
          </Box>
        </Box>
      )}
    </Drawer>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <Stack direction="row" spacing={2} sx={{ borderBottom: 1, borderColor: "divider", py: 1 }}>
      <Typography variant="caption" sx={{ color: "text.secondary", minWidth: 100 }}>
        {label}
      </Typography>
      <Typography
        variant="body2"
        sx={{ fontFamily: "monospace", textAlign: "right", flex: 1, wordBreak: "break-all" }}
      >
        {value}
      </Typography>
    </Stack>
  );
}

function CodeBlock({ content }: { content: string }) {
  return (
    <Box
      component="pre"
      sx={{
        bgcolor: "action.hover",
        borderRadius: 2,
        p: 1.5,
        fontFamily: "monospace",
        fontSize: "0.75rem",
        maxHeight: 384,
        overflow: "auto",
        whiteSpace: "pre",
      }}
    >
      {content}
    </Box>
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
