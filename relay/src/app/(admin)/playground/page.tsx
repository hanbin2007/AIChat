"use client";

import { useCallback, useRef, useState } from "react";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import TextField from "@mui/material/TextField";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Select from "@mui/material/Select";
import MenuItem from "@mui/material/MenuItem";
import FormControl from "@mui/material/FormControl";
import InputLabel from "@mui/material/InputLabel";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import ToggleButton from "@mui/material/ToggleButton";
import Chip from "@mui/material/Chip";
import Accordion from "@mui/material/Accordion";
import AccordionSummary from "@mui/material/AccordionSummary";
import AccordionDetails from "@mui/material/AccordionDetails";
import VisibilityRounded from "@mui/icons-material/VisibilityRounded";
import VisibilityOffRounded from "@mui/icons-material/VisibilityOffRounded";
import SendRounded from "@mui/icons-material/SendRounded";
import ExpandMoreRounded from "@mui/icons-material/ExpandMoreRounded";
import { Markdown } from "@/components/markdown";
import { useSetPageActions } from "@/components/shell/page-meta";
import { DEFAULT_MODELS } from "@/lib/gemini/models";

type Intensity = "fast" | "balanced" | "deep" | "extreme";

interface Message {
  id: string;
  role: "user" | "assistant";
  text: string;
  thought?: string;
  finishReason?: string;
  error?: string;
}

interface RawEvent {
  at: string;
  type: string;
  data: string;
}

const INTENSITIES: Intensity[] = ["fast", "balanced", "deep", "extreme"];

export default function PlaygroundPage() {
  const [model, setModel] = useState(DEFAULT_MODELS[0]?.id ?? "");
  const [intensity, setIntensity] = useState<Intensity>("balanced");
  const [search, setSearch] = useState(false);
  const [code, setCode] = useState(false);
  const [token, setToken] = useState("");
  const [system, setSystem] = useState("");
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [events, setEvents] = useState<RawEvent[]>([]);
  const [showRaw, setShowRaw] = useState(true);
  const [streaming, setStreaming] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  const send = useCallback(async () => {
    const text = draft.trim();
    if (!text || streaming) return;
    setDraft("");
    const userMsg: Message = {
      id: `u-${Date.now()}`,
      role: "user",
      text,
    };
    const assistantMsg: Message = {
      id: `a-${Date.now()}`,
      role: "assistant",
      text: "",
      thought: "",
    };
    setMessages((prev) => [...prev, userMsg, assistantMsg]);
    setStreaming(true);

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const res = await fetch("/api/v1/chat/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        signal: controller.signal,
        body: JSON.stringify({
          model,
          thinking: { intensity },
          tools: { search, codeExecution: code },
          system: system || undefined,
          messages: [...messages.filter((m) => m.role === "user").map((m) => ({ role: "user", content: m.text })), { role: "user", content: text }],
        }),
      });
      if (!res.ok || !res.body) {
        const errText = await res.text().catch(() => "");
        setMessages((prev) =>
          prev.map((m) =>
            m.id === assistantMsg.id ? { ...m, error: errText || `HTTP ${res.status}` } : m,
          ),
        );
        return;
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let currentEvent = "";
      let currentData = "";
      const flushEvent = (eventName: string, dataLine: string) => {
        const at = new Date().toISOString();
        setEvents((prev) => [...prev, { at, type: eventName, data: dataLine }].slice(-100));
        try {
          const parsed = JSON.parse(dataLine) as { delta?: string; reason?: string };
          if (eventName === "answer_delta" && parsed.delta) {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === assistantMsg.id ? { ...m, text: m.text + parsed.delta } : m,
              ),
            );
          } else if (eventName === "thought_delta" && parsed.delta) {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === assistantMsg.id ? { ...m, thought: (m.thought ?? "") + parsed.delta } : m,
              ),
            );
          } else if (eventName === "done" && parsed.reason) {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === assistantMsg.id ? { ...m, finishReason: parsed.reason } : m,
              ),
            );
          } else if (eventName === "error") {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === assistantMsg.id ? { ...m, error: dataLine } : m,
              ),
            );
          }
        } catch {
          /* ignore */
        }
      };

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          if (line === "") {
            if (currentEvent || currentData) flushEvent(currentEvent || "message", currentData);
            currentEvent = "";
            currentData = "";
          } else if (line.startsWith("event:")) {
            currentEvent = line.slice(6).trim();
          } else if (line.startsWith("data:")) {
            currentData += (currentData ? "\n" : "") + line.slice(5).trimStart();
          }
        }
      }
    } catch (err) {
      if ((err as Error).name !== "AbortError") {
        setMessages((prev) =>
          prev.map((m) =>
            m.id === assistantMsg.id ? { ...m, error: String(err) } : m,
          ),
        );
      }
    } finally {
      abortRef.current = null;
      setStreaming(false);
    }
  }, [draft, model, intensity, search, code, token, system, messages, streaming]);

  useSetPageActions(
    <Tooltip title={showRaw ? "隐藏原始事件" : "显示原始事件"}>
      <IconButton aria-label="切换原始事件" onClick={() => setShowRaw((v) => !v)}>
        {showRaw ? <VisibilityRounded /> : <VisibilityOffRounded />}
      </IconButton>
    </Tooltip>,
    [showRaw],
  );

  return (
    <>
      <Box
        sx={{
          display: "grid",
          gridTemplateColumns: { xs: "1fr", md: showRaw ? "1fr 360px" : "1fr" },
          gap: 2,
          height: "calc(100vh - 140px)",
        }}
      >
        <Card sx={{ display: "flex", flexDirection: "column", overflow: "hidden" }}>
          <Box sx={{ p: 2, borderBottom: 1, borderColor: "divider" }}>
            <Stack direction={{ xs: "column", lg: "row" }} spacing={1.5} alignItems={{ lg: "center" }}>
              <FormControl size="small" sx={{ minWidth: 220 }}>
                <InputLabel>模型</InputLabel>
                <Select
                  label="模型"
                  value={model}
                  onChange={(e) => setModel(e.target.value)}
                >
                  {DEFAULT_MODELS.map((m) => (
                    <MenuItem key={m.id} value={m.id}>
                      {m.displayName}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
              <ToggleButtonGroup
                exclusive
                size="small"
                value={intensity}
                onChange={(_e, v: Intensity | null) => {
                  if (v) setIntensity(v);
                }}
              >
                {INTENSITIES.map((i) => (
                  <ToggleButton key={i} value={i}>
                    {i}
                  </ToggleButton>
                ))}
              </ToggleButtonGroup>
              <Stack direction="row" spacing={1}>
                <Chip
                  label="Search"
                  variant={search ? "filled" : "outlined"}
                  color={search ? "primary" : "default"}
                  onClick={() => setSearch((v) => !v)}
                />
                <Chip
                  label="Code"
                  variant={code ? "filled" : "outlined"}
                  color={code ? "primary" : "default"}
                  onClick={() => setCode((v) => !v)}
                />
              </Stack>
            </Stack>
            <Stack direction={{ xs: "column", md: "row" }} spacing={1.5} sx={{ mt: 1.5 }}>
              <TextField
                label="Authorization (可选)"
                size="small"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                placeholder="Bearer xxx"
                fullWidth
              />
              <TextField
                label="System prompt (可选)"
                size="small"
                value={system}
                onChange={(e) => setSystem(e.target.value)}
                fullWidth
              />
            </Stack>
          </Box>

          <Box sx={{ flex: 1, overflow: "auto", p: 2 }}>
            <Stack spacing={2}>
              {messages.length === 0 ? (
                <Typography color="text.secondary" sx={{ textAlign: "center", py: 4 }}>
                  发起对话以测试 /api/v1/chat/stream
                </Typography>
              ) : null}
              {messages.map((m) => (
                <Card
                  key={m.id}
                  variant="outlined"
                  sx={{
                    bgcolor: m.role === "user" ? "action.hover" : "background.paper",
                  }}
                >
                  <CardContent>
                    <Typography variant="caption" color="text.secondary">
                      {m.role === "user" ? "用户" : "助手"}
                    </Typography>
                    {m.role === "assistant" && m.thought ? (
                      <Accordion sx={{ mb: 1, mt: 1 }}>
                        <AccordionSummary expandIcon={<ExpandMoreRounded />}>
                          <Typography variant="caption">
                            💭 思考 · {m.thought.length} 字符
                          </Typography>
                        </AccordionSummary>
                        <AccordionDetails>
                          <Markdown source={m.thought} />
                        </AccordionDetails>
                      </Accordion>
                    ) : null}
                    {m.text ? (
                      <Markdown source={m.text} />
                    ) : (
                      <Typography variant="body2" color="text.secondary">
                        {streaming && m.role === "assistant" ? "等待响应…" : ""}
                      </Typography>
                    )}
                    {m.finishReason && m.finishReason !== "STOP" ? (
                      <Typography variant="caption" color="warning.main" sx={{ mt: 1 }}>
                        finishReason: {m.finishReason}
                      </Typography>
                    ) : null}
                    {m.error ? (
                      <Typography variant="caption" color="error.main" sx={{ display: "block", mt: 1 }}>
                        {m.error}
                      </Typography>
                    ) : null}
                  </CardContent>
                </Card>
              ))}
            </Stack>
          </Box>

          <Box sx={{ p: 2, borderTop: 1, borderColor: "divider" }}>
            <Stack direction="row" spacing={1.5}>
              <TextField
                multiline
                minRows={1}
                maxRows={6}
                placeholder="输入消息…（Enter 发送，Shift+Enter 换行）"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    void send();
                  }
                }}
                fullWidth
              />
              <Button
                variant="contained"
                disabled={!draft.trim() || streaming}
                onClick={() => void send()}
                startIcon={<SendRounded />}
              >
                {streaming ? "发送中…" : "发送"}
              </Button>
            </Stack>
          </Box>
        </Card>

        {showRaw ? (
          <Card sx={{ display: "flex", flexDirection: "column", overflow: "hidden" }}>
            <Box sx={{ p: 2, borderBottom: 1, borderColor: "divider" }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
                原始 SSE 事件
              </Typography>
              <Typography variant="caption" color="text.secondary">
                最近 100 条
              </Typography>
            </Box>
            <Box sx={{ flex: 1, overflow: "auto", p: 1.5, fontFamily: "var(--font-mono)" }}>
              {events.length === 0 ? (
                <Typography variant="caption" color="text.secondary">
                  无事件
                </Typography>
              ) : (
                events.map((e, i) => (
                  <Box key={i} sx={{ mb: 1 }}>
                    <Typography
                      variant="caption"
                      color="text.secondary"
                      sx={{ display: "block" }}
                    >
                      {e.at.slice(11, 23)} · {e.type}
                    </Typography>
                    <Box
                      component="pre"
                      sx={{
                        m: 0,
                        whiteSpace: "pre-wrap",
                        fontSize: "0.75rem",
                        wordBreak: "break-all",
                      }}
                    >
                      {e.data}
                    </Box>
                  </Box>
                ))
              )}
            </Box>
          </Card>
        ) : null}
      </Box>
    </>
  );
}
