"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ComponentType } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import TextField from "@mui/material/TextField";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import ToggleButton from "@mui/material/ToggleButton";
import Drawer from "@mui/material/Drawer";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Divider from "@mui/material/Divider";
import RefreshRounded from "@mui/icons-material/RefreshRounded";
import PauseRounded from "@mui/icons-material/PauseRounded";
import PlayArrowRounded from "@mui/icons-material/PlayArrowRounded";
import CloseRounded from "@mui/icons-material/CloseRounded";
import VisibilityRounded from "@mui/icons-material/VisibilityRounded";
import type { DataGridProps, GridColDef, GridRowParams } from "@mui/x-data-grid";
import { useSnackbar } from "@/components/snackbar-provider";
import { useSetPageActions } from "@/components/shell/page-meta";
import type { ActivityEntry } from "@/lib/store/request-log";
import type { Conversation } from "@/lib/store/conversations";

type TabKey = "live" | "history" | "conversations";
type LoadState = "loading" | "ready" | "error";

const DataGrid = dynamic(() => import("@mui/x-data-grid").then((mod) => mod.DataGrid), {
  ssr: false,
  loading: () => <EmptyState message="正在加载表格…" />,
}) as ComponentType<DataGridProps<ActivityEntry>>;

const Markdown = dynamic(() => import("@/components/markdown").then((mod) => mod.Markdown), {
  ssr: false,
  loading: () => <Typography variant="body2" color="text.secondary">正在加载渲染器…</Typography>,
});

const LEVELS: Array<ActivityEntry["level"]> = ["info", "success", "warning", "error"];

function levelColor(level: string): "default" | "info" | "success" | "warning" | "error" {
  if (level === "error") return "error";
  if (level === "warning") return "warning";
  if (level === "success") return "success";
  if (level === "info") return "info";
  return "default";
}

export default function RequestsPage() {
  const snackbar = useSnackbar();
  const [tab, setTab] = useState<TabKey>("live");
  const [history, setHistory] = useState<ActivityEntry[]>([]);
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [historyState, setHistoryState] = useState<LoadState>("loading");
  const [conversationState, setConversationState] = useState<LoadState>("loading");
  const [streamState, setStreamState] = useState<"connecting" | "live" | "paused" | "error">(
    "connecting",
  );
  const [paused, setPaused] = useState(false);
  const [search, setSearch] = useState("");
  const [activeLevels, setActiveLevels] = useState<string[]>([...LEVELS]);
  const [selected, setSelected] = useState<ActivityEntry | null>(null);
  const [drawerTab, setDrawerTab] = useState(0);
  const eventRef = useRef<EventSource | null>(null);
  const liveRef = useRef<ActivityEntry[]>([]);
  const [liveTick, setLiveTick] = useState(0);

  const fetchHistory = useCallback(async () => {
    setHistoryState("loading");
    try {
      const res = await fetch("/api/admin/requests");
      if (!res.ok) throw new Error("拉取请求日志失败");
      const data = (await res.json()) as { requests: ActivityEntry[] };
      setHistory(data.requests);
      setHistoryState("ready");
    } catch {
      setHistoryState("error");
      snackbar.push({ message: "拉取请求日志失败", severity: "error" });
    }
  }, [snackbar]);

  const fetchConversations = useCallback(async () => {
    setConversationState("loading");
    try {
      const res = await fetch("/api/admin/conversations");
      if (!res.ok) throw new Error("拉取对话失败");
      const data = (await res.json()) as { conversations: Conversation[] };
      setConversations(data.conversations);
      setConversationState("ready");
    } catch {
      setConversationState("error");
      snackbar.push({ message: "拉取对话失败", severity: "error" });
    }
  }, [snackbar]);

  useEffect(() => {
    void fetchHistory();
    void fetchConversations();
  }, [fetchHistory, fetchConversations]);

  useEffect(() => {
    if (paused) {
      setStreamState("paused");
      return;
    }
    setStreamState("connecting");
    const es = new EventSource("/api/admin/requests/stream");
    eventRef.current = es;
    es.onopen = () => setStreamState("live");
    es.addEventListener("activity", (event) => {
      try {
        const entry = JSON.parse((event as MessageEvent).data) as ActivityEntry;
        liveRef.current = [entry, ...liveRef.current].slice(0, 200);
        setLiveTick((t) => t + 1);
      } catch {
        /* ignore parse errors */
      }
    });
    es.onerror = () => {
      setStreamState("error");
      es.close();
    };
    return () => {
      es.close();
      eventRef.current = null;
    };
  }, [paused]);

  const rows = useMemo<ActivityEntry[]>(() => {
    const source = tab === "live" ? liveRef.current : history;
    const q = search.trim().toLowerCase();
    return source.filter((row) => {
      if (!activeLevels.includes(row.level)) return false;
      if (!q) return true;
      return (
        (row.path ?? "").toLowerCase().includes(q) ||
        (row.message ?? "").toLowerCase().includes(q) ||
        (row.modelID ?? "").toLowerCase().includes(q) ||
        (row.accountID ?? "").toLowerCase().includes(q) ||
        (row.accountName ?? "").toLowerCase().includes(q)
      );
    });
  }, [tab, history, activeLevels, search, liveTick]);

  const columns = useMemo<GridColDef<ActivityEntry>[]>(
    () => [
      {
        field: "actions",
        headerName: " ",
        width: 76,
        sortable: false,
        renderCell: (params) => (
          <Tooltip title="查看详情">
            <IconButton
              aria-label="查看详情"
              size="small"
              onClick={(event) => {
                event.stopPropagation();
                setSelected(params.row);
                setDrawerTab(0);
              }}
            >
              <VisibilityRounded fontSize="small" />
            </IconButton>
          </Tooltip>
        ),
      },
      {
        field: "timestamp",
        headerName: "时间",
        width: 180,
        valueGetter: (_v, row) => new Date(row.timestamp).toLocaleString("zh-Hans"),
      },
      {
        field: "path",
        headerName: "端点",
        flex: 1.4,
        minWidth: 220,
        renderCell: (params) => (
          <Box sx={{ fontFamily: "var(--font-mono)", fontSize: "0.8125rem" }}>
            {params.row.method ? `${params.row.method} ` : ""}
            {params.row.path ?? params.row.message}
          </Box>
        ),
      },
      {
        field: "statusCode",
        headerName: "状态",
        width: 100,
        renderCell: (params) => (
          <Chip
            size="small"
            label={params.row.statusCode ?? params.row.level}
            color={levelColor(params.row.level)}
          />
        ),
      },
      {
        field: "latencyMs",
        headerName: "延迟",
        width: 100,
        valueGetter: (_v, row) => (row.latencyMs != null ? `${row.latencyMs}ms` : "—"),
      },
      {
        field: "tokens",
        headerName: "Tokens",
        width: 140,
        valueGetter: (_v, row) =>
          `${row.inputTokens ?? 0} → ${row.outputTokens ?? 0}`,
      },
      {
        field: "modelID",
        headerName: "模型",
        flex: 1,
        minWidth: 160,
      },
      {
        field: "deviceAlias",
        headerName: "设备",
        flex: 0.8,
        minWidth: 120,
        valueGetter: (_v, row) => row.deviceAlias ?? row.deviceID ?? "—",
      },
      {
        field: "settledCredits",
        headerName: "Credits",
        width: 100,
        valueGetter: (_v, row) =>
          row.settledCredits ?? row.reservedCredits ?? "—",
      },
    ],
    [],
  );

  const liveOrHistory = tab === "live" || tab === "history";

  useSetPageActions(
    liveOrHistory ? (
      <>
        {tab === "live" ? (
          <Tooltip title={paused ? "恢复实时" : "暂停实时"}>
            <IconButton
              aria-label={paused ? "恢复" : "暂停"}
              onClick={() => setPaused((p) => !p)}
            >
              {paused ? <PlayArrowRounded /> : <PauseRounded />}
            </IconButton>
          </Tooltip>
        ) : null}
        <Tooltip title="刷新">
          <IconButton aria-label="刷新" onClick={() => void fetchHistory()}>
            <RefreshRounded />
          </IconButton>
        </Tooltip>
      </>
    ) : null,
    [tab, paused, liveOrHistory],
  );

  return (
    <>
      <Stack spacing={2}>
        <Card>
          <CardContent>
            <Stack
              direction={{ xs: "column", md: "row" }}
              spacing={2}
              alignItems={{ md: "center" }}
            >
              <ToggleButtonGroup
                aria-label="请求日志视图"
                exclusive
                value={tab}
                onChange={(_e, v) => {
                  if (v) setTab(v as TabKey);
                }}
                size="small"
              >
                <ToggleButton value="live">实时</ToggleButton>
                <ToggleButton value="history">历史</ToggleButton>
                <ToggleButton value="conversations">对话</ToggleButton>
              </ToggleButtonGroup>
              <TextField
                size="small"
                label="搜索请求"
                placeholder="路径 / 模型 / 账户"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                sx={{ flex: 1, maxWidth: 360 }}
              />
              <Stack direction="row" spacing={1} flexWrap="wrap">
                {LEVELS.map((lv) => (
                  <Chip
                    key={lv}
                    label={lv}
                    color={activeLevels.includes(lv) ? levelColor(lv) : "default"}
                    variant={activeLevels.includes(lv) ? "filled" : "outlined"}
                    onClick={() =>
                      setActiveLevels((prev) =>
                        prev.includes(lv) ? prev.filter((p) => p !== lv) : [...prev, lv],
                      )
                    }
                  />
                ))}
              </Stack>
            </Stack>
          </CardContent>
        </Card>

        {liveOrHistory ? (
          <Card>
            {tab === "live" ? (
              <Box sx={{ px: 2, pt: 1.5 }}>
                <Chip
                  size="small"
                  label={
                    streamState === "live"
                      ? "实时连接中"
                      : streamState === "paused"
                        ? "已暂停"
                        : streamState === "error"
                          ? "实时流已断开"
                          : "正在连接实时流"
                  }
                  color={streamState === "error" ? "error" : streamState === "live" ? "success" : "default"}
                  variant={streamState === "live" ? "filled" : "outlined"}
                />
              </Box>
            ) : null}
            <Box sx={{ height: 600 }}>
              {tab === "history" && historyState === "error" ? (
                <EmptyState message="请求日志加载失败" actionLabel="重试" onAction={() => void fetchHistory()} />
              ) : (
              <DataGrid
                rows={rows}
                columns={columns}
                getRowId={(r) => r.id}
                onRowClick={(p: GridRowParams<ActivityEntry>) => {
                  setSelected(p.row);
                  setDrawerTab(0);
                }}
                density="compact"
                pageSizeOptions={[25, 50, 100]}
                initialState={{ pagination: { paginationModel: { pageSize: 25 } } }}
                sx={{ border: "none" }}
              />
              )}
            </Box>
          </Card>
        ) : (
          <Card>
            <Box>
              {conversationState === "loading" ? (
                <EmptyState message="正在加载对话…" />
              ) : conversationState === "error" ? (
                <EmptyState message="对话加载失败" actionLabel="重试" onAction={() => void fetchConversations()} />
              ) : conversations.length === 0 ? (
                <EmptyState message="暂无对话记录" />
              ) : (
                <Box>
                  {conversations.map((c, i) => (
                    <Box key={c.id}>
                      <Box
                        component={Link}
                        href={`/requests/conversations/${c.id}`}
                        sx={{
                          display: "block",
                          p: 2,
                          color: "inherit",
                          textDecoration: "none",
                          "&:hover": { bgcolor: "action.hover" },
                        }}
                      >
                        <Stack direction="row" spacing={2} alignItems="center">
                          <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 700 }} noWrap>
                              {c.title}
                            </Typography>
                            <Typography
                              variant="caption"
                              color="text.secondary"
                              sx={{ fontFamily: "var(--font-mono)" }}
                            >
                              {c.id}
                            </Typography>
                          </Box>
                          <Stack direction="row" spacing={1} alignItems="center">
                            {c.hasErrors ? <Chip size="small" label="错误" color="error" /> : null}
                            {c.hasImages ? <Chip size="small" label="图片" /> : null}
                            {c.hasAudio ? <Chip size="small" label="音频" /> : null}
                            <Chip
                              size="small"
                              label={c.confidence === "high" ? "高置信" : "低置信"}
                              variant="outlined"
                            />
                          </Stack>
                          <Typography
                            variant="caption"
                            color="text.secondary"
                            sx={{ fontFamily: "var(--font-mono)", minWidth: 80, textAlign: "right" }}
                          >
                            {c.turnCount} 轮
                          </Typography>
                        </Stack>
                      </Box>
                      {i < conversations.length - 1 ? <Divider /> : null}
                    </Box>
                  ))}
                </Box>
              )}
            </Box>
          </Card>
        )}
      </Stack>

      <Drawer
        anchor="right"
        open={Boolean(selected)}
        onClose={() => setSelected(null)}
        aria-labelledby="request-detail-title"
        slotProps={{ paper: { sx: { width: { xs: "100%", sm: 520 } } } }}
      >
        {selected ? (
          <Box sx={{ display: "flex", flexDirection: "column", height: "100%" }}>
            <Box sx={{ p: 2, borderBottom: 1, borderColor: "divider" }}>
              <Stack direction="row" spacing={1} alignItems="center">
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Typography id="request-detail-title" variant="subtitle1" sx={{ fontWeight: 700 }} noWrap>
                    {selected.method ? `${selected.method} ` : ""}
                    {selected.path ?? selected.message}
                  </Typography>
                  <Typography
                    variant="caption"
                    color="text.secondary"
                    sx={{ fontFamily: "var(--font-mono)" }}
                  >
                    {selected.id} · {new Date(selected.timestamp).toLocaleString("zh-Hans")}
                  </Typography>
                </Box>
                <IconButton aria-label="关闭" onClick={() => setSelected(null)}>
                  <CloseRounded />
                </IconButton>
              </Stack>
              <Tabs
                value={drawerTab}
                onChange={(_e, v: number) => setDrawerTab(v)}
                sx={{ mt: 1 }}
              >
                <Tab label="请求" />
                <Tab label="响应" />
                <Tab label="事件" />
              </Tabs>
            </Box>
            <Box sx={{ flex: 1, overflow: "auto", p: 2 }}>
              {drawerTab === 0 ? (
                <Box
                  component="pre"
                  sx={{
                    fontFamily: "var(--font-mono)",
                    fontSize: "0.8125rem",
                    whiteSpace: "pre-wrap",
                    m: 0,
                  }}
                >
                  {JSON.stringify(selected.requestBody ?? null, null, 2)}
                </Box>
              ) : null}
              {drawerTab === 1 ? (
                selected.responseSummary ? (
                  <Markdown source={selected.responseSummary} />
                ) : (
                  <Typography variant="body2" color="text.secondary">
                    无响应摘要
                  </Typography>
                )
              ) : null}
              {drawerTab === 2 ? (
                <Stack spacing={1}>
                  {(selected.events ?? []).length === 0 ? (
                    <Typography variant="body2" color="text.secondary">
                      无事件
                    </Typography>
                  ) : (
                    (selected.events ?? []).map((e, i) => (
                      <Box key={i}>
                        <Typography
                          variant="caption"
                          color="text.secondary"
                          sx={{ fontFamily: "var(--font-mono)" }}
                        >
                          {e.at} · {e.type}
                        </Typography>
                        <Box
                          component="pre"
                          sx={{
                            fontFamily: "var(--font-mono)",
                            fontSize: "0.75rem",
                            whiteSpace: "pre-wrap",
                            m: 0,
                            bgcolor: "action.hover",
                            p: 1,
                            borderRadius: 1,
                          }}
                        >
                          {typeof e.data === "string" ? e.data : JSON.stringify(e.data, null, 2)}
                        </Box>
                      </Box>
                    ))
                  )}
                </Stack>
              ) : null}
            </Box>
          </Box>
        ) : null}
      </Drawer>
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
    <Box sx={{ p: 6, textAlign: "center" }}>
      <Stack spacing={1.5} alignItems="center">
        <Typography color="text.secondary">{message}</Typography>
        {actionLabel && onAction ? (
          <Chip clickable label={actionLabel} onClick={onAction} variant="outlined" />
        ) : null}
      </Stack>
    </Box>
  );
}
