"use client";
import * as React from "react";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import TextField from "@mui/material/TextField";
import Select from "@mui/material/Select";
import MenuItem from "@mui/material/MenuItem";
import FormControl from "@mui/material/FormControl";
import InputLabel from "@mui/material/InputLabel";
import Chip from "@mui/material/Chip";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import ToggleButton from "@mui/material/ToggleButton";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import Accordion from "@mui/material/Accordion";
import AccordionSummary from "@mui/material/AccordionSummary";
import AccordionDetails from "@mui/material/AccordionDetails";
import Divider from "@mui/material/Divider";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import SendIcon from "@mui/icons-material/Send";
import ForumIcon from "@mui/icons-material/Forum";
import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import TravelExploreIcon from "@mui/icons-material/TravelExplore";
import CodeIcon from "@mui/icons-material/Code";
import { AppShell } from "@/components/shell/app-shell";

type Intensity = "fast" | "balanced" | "deep" | "extreme";

interface Message {
  id: string;
  role: "user" | "assistant";
  text: string;
  thought?: string;
  attachments?: { mimeType: string; base64Data: string }[];
  finishReason?: string;
}

const MODELS = ["gemini-3-flash-preview", "gemini-3.1-pro-preview", "gemini-2.5-flash"];
const INTENSITIES: Intensity[] = ["fast", "balanced", "deep", "extreme"];

export default function PlaygroundPage() {
  const [bearer, setBearer] = React.useState("");
  const [model, setModel] = React.useState(MODELS[0]);
  const [intensity, setIntensity] = React.useState<Intensity>("balanced");
  const [search, setSearch] = React.useState(false);
  const [codeExec, setCodeExec] = React.useState(false);
  const [systemPrompt, setSystemPrompt] = React.useState("");
  const [messages, setMessages] = React.useState<Message[]>([]);
  const [input, setInput] = React.useState("");
  const [streaming, setStreaming] = React.useState(false);
  const [rawEvents, setRawEvents] = React.useState<string[]>([]);
  const [rawOpen, setRawOpen] = React.useState(false);

  async function send() {
    if (!input.trim() || streaming) return;
    const userMessage: Message = { id: crypto.randomUUID(), role: "user", text: input };
    const assistant: Message = { id: crypto.randomUUID(), role: "assistant", text: "", thought: "" };
    const history = [...messages, userMessage];
    setMessages([...history, assistant]);
    setInput("");
    setStreaming(true);
    setRawEvents([]);

    try {
      const payload = {
        model,
        systemPrompt: systemPrompt || undefined,
        thinkingIntensity: intensity,
        usesGoogleSearch: search,
        usesCodeExecution: codeExec,
        includeThoughts: true,
        messages: history.map((m) => ({ role: m.role, text: m.text })),
      };
      const res = await fetch("/api/v1/chat/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}),
        },
        body: JSON.stringify(payload),
      });
      if (!res.ok || !res.body) {
        const err = await res.text().catch(() => "");
        updateAssistant(assistant.id, (m) => ({ ...m, text: `错误：${err || res.statusText}` }));
        return;
      }
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffered = "";
      let currentEvent = "";
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffered += decoder.decode(value, { stream: true });
        const lines = buffered.split("\n");
        buffered = lines.pop() ?? "";
        for (const line of lines) {
          if (line.startsWith("event:")) {
            currentEvent = line.slice(6).trim();
          } else if (line.startsWith("data:")) {
            const data = line.slice(5).trim();
            if (!data) continue;
            setRawEvents((prev) => [...prev.slice(-99), `${currentEvent}: ${data}`]);
            try {
              const parsed = JSON.parse(data);
              if (currentEvent === "answer_delta") {
                updateAssistant(assistant.id, (m) => ({ ...m, text: m.text + (parsed.text ?? "") }));
              } else if (currentEvent === "thought_delta") {
                updateAssistant(assistant.id, (m) => ({ ...m, thought: (m.thought ?? "") + (parsed.text ?? "") }));
              } else if (currentEvent === "done") {
                updateAssistant(assistant.id, (m) => ({ ...m, finishReason: parsed.finishReason }));
              } else if (currentEvent === "error") {
                updateAssistant(assistant.id, (m) => ({ ...m, text: m.text + `\n\n[error: ${parsed.message}]` }));
              }
            } catch {
              /* ignore */
            }
          }
        }
      }
    } finally {
      setStreaming(false);
    }
  }

  function updateAssistant(id: string, updater: (m: Message) => Message) {
    setMessages((prev) => prev.map((m) => (m.id === id ? updater(m) : m)));
  }

  return (
    <AppShell title="Playground" breadcrumb={["Relay"]}>
      <Box
        sx={{
          height: "calc(100vh - 64px)",
          display: "grid",
          gridTemplateColumns: { xs: "1fr", md: "1fr 360px" },
        }}
      >
        <Box sx={{ display: "flex", flexDirection: "column", minHeight: 0 }}>
          <Box
            sx={{
              p: 2,
              borderBottom: 1,
              borderColor: "divider",
              bgcolor: "background.default",
              position: "sticky",
              top: 0,
              zIndex: 1,
            }}
          >
            <Stack spacing={2}>
              <Stack direction="row" spacing={1.5} flexWrap="wrap" useFlexGap alignItems="center">
                <FormControl size="small" sx={{ minWidth: 220 }}>
                  <InputLabel id="model-select">Model</InputLabel>
                  <Select
                    labelId="model-select"
                    label="Model"
                    value={model}
                    onChange={(e) => setModel(e.target.value)}
                  >
                    {MODELS.map((m) => (
                      <MenuItem key={m} value={m}>
                        {m}
                      </MenuItem>
                    ))}
                  </Select>
                </FormControl>
                <Stack direction="row" spacing={1} alignItems="center">
                  <Typography variant="caption" sx={{ color: "text.secondary" }}>
                    思考强度
                  </Typography>
                  <ToggleButtonGroup
                    size="small"
                    value={intensity}
                    exclusive
                    onChange={(_, v) => v && setIntensity(v as Intensity)}
                  >
                    {INTENSITIES.map((i) => (
                      <ToggleButton key={i} value={i}>
                        {i}
                      </ToggleButton>
                    ))}
                  </ToggleButtonGroup>
                </Stack>
                <Chip
                  icon={<TravelExploreIcon />}
                  label="Google Search"
                  color={search ? "primary" : "default"}
                  variant={search ? "filled" : "outlined"}
                  onClick={() => setSearch((v) => !v)}
                />
                <Chip
                  icon={<CodeIcon />}
                  label="Code Execution"
                  color={codeExec ? "primary" : "default"}
                  variant={codeExec ? "filled" : "outlined"}
                  onClick={() => setCodeExec((v) => !v)}
                />
              </Stack>
              <TextField
                label="Authorization bearer"
                placeholder="为空时使用 session — 仅可调 admin token；填入 rk_... 可走客户端路径测试计费"
                value={bearer}
                onChange={(e) => setBearer(e.target.value)}
                size="small"
              />
              <TextField
                label="System prompt"
                value={systemPrompt}
                onChange={(e) => setSystemPrompt(e.target.value)}
                size="small"
                multiline
                maxRows={3}
              />
            </Stack>
          </Box>

          <Box sx={{ flex: 1, overflow: "auto", p: 2 }}>
            {messages.length === 0 && (
              <Stack alignItems="center" sx={{ py: 8, color: "text.secondary" }}>
                <ForumIcon sx={{ fontSize: 48, opacity: 0.4 }} />
                <Typography variant="body2" sx={{ mt: 1.5 }}>
                  输入消息开始对话
                </Typography>
              </Stack>
            )}
            <Stack spacing={2}>
              {messages.map((m) => (
                <Box
                  key={m.id}
                  sx={{
                    display: "flex",
                    justifyContent: m.role === "user" ? "flex-end" : "flex-start",
                  }}
                >
                  <Box
                    sx={{
                      maxWidth: 640,
                      whiteSpace: "pre-wrap",
                      px: 2,
                      py: 1.5,
                      borderRadius: 2,
                      bgcolor: m.role === "user" ? "primary.main" : "action.hover",
                      color: m.role === "user" ? "primary.contrastText" : "text.primary",
                      borderBottomRightRadius: m.role === "user" ? 4 : 16,
                      borderBottomLeftRadius: m.role === "user" ? 16 : 4,
                    }}
                  >
                    {m.thought && m.role === "assistant" && (
                      <Accordion
                        disableGutters
                        elevation={0}
                        square
                        sx={{ bgcolor: "transparent", mb: 1, "&:before": { display: "none" } }}
                      >
                        <AccordionSummary
                          expandIcon={<ExpandMoreIcon fontSize="small" />}
                          sx={{ minHeight: 0, px: 0, py: 0 }}
                        >
                          <Typography variant="caption" sx={{ fontStyle: "italic", color: "text.secondary" }}>
                            💭 Thought · {m.thought.length} chars
                          </Typography>
                        </AccordionSummary>
                        <AccordionDetails sx={{ px: 0, pb: 0 }}>
                          <Typography
                            variant="caption"
                            component="div"
                            sx={{
                              whiteSpace: "pre-wrap",
                              fontStyle: "italic",
                              color: "text.secondary",
                              borderLeft: 2,
                              borderColor: "divider",
                              pl: 1,
                            }}
                          >
                            {m.thought}
                          </Typography>
                        </AccordionDetails>
                      </Accordion>
                    )}
                    <Typography variant="body2" component="div" sx={{ whiteSpace: "pre-wrap" }}>
                      {m.text || (m.role === "assistant" && streaming ? "…" : "")}
                    </Typography>
                    {m.finishReason && m.finishReason !== "STOP" && (
                      <Typography variant="caption" sx={{ display: "block", mt: 1, color: "text.secondary" }}>
                        finishReason: {m.finishReason}
                      </Typography>
                    )}
                  </Box>
                </Box>
              ))}
            </Stack>
          </Box>

          <Box
            sx={{
              p: 2,
              borderTop: 1,
              borderColor: "divider",
              bgcolor: "action.hover",
              display: "flex",
              alignItems: "flex-end",
              gap: 1,
            }}
          >
            <TextField
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="输入消息，Enter 发送，Shift+Enter 换行"
              multiline
              minRows={2}
              maxRows={6}
              size="small"
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  send();
                }
              }}
              sx={{ flex: 1 }}
            />
            <Button
              startIcon={<SendIcon />}
              onClick={send}
              disabled={!input.trim() || streaming}
            >
              {streaming ? "处理中…" : "发送"}
            </Button>
          </Box>
        </Box>

        <Box
          component="aside"
          sx={{
            display: { xs: "none", md: "flex" },
            flexDirection: "column",
            borderLeft: 1,
            borderColor: "divider",
            bgcolor: "action.hover",
          }}
        >
          <Box sx={{ p: 2, borderBottom: 1, borderColor: "divider", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <Typography variant="subtitle2">Raw SSE</Typography>
            <Tooltip title={rawOpen ? "隐藏原始事件" : "显示原始事件"}>
              <IconButton size="small" onClick={() => setRawOpen((v) => !v)}>
                {rawOpen ? <VisibilityOffIcon fontSize="small" /> : <VisibilityIcon fontSize="small" />}
              </IconButton>
            </Tooltip>
          </Box>
          <Divider />
          <Box sx={{ flex: 1, overflow: "auto", p: 1.5 }}>
            {rawOpen ? (
              rawEvents.length === 0 ? (
                <Typography variant="caption" sx={{ color: "text.secondary" }}>
                  尚未收到事件
                </Typography>
              ) : (
                <Stack component="ul" spacing={0.25} sx={{ p: 0, m: 0, listStyle: "none", fontFamily: "monospace", fontSize: "0.75rem" }}>
                  {rawEvents.map((e, i) => (
                    <Box key={i} component="li" sx={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {e}
                    </Box>
                  ))}
                </Stack>
              )
            ) : (
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                点击眼睛图标查看原始 SSE 事件
              </Typography>
            )}
          </Box>
        </Box>
      </Box>
    </AppShell>
  );
}
