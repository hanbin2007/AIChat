"use client";
import * as React from "react";
import { AdminShell } from "@/components/admin-shell";
import { Button, Card, CardContent, CardHeader, CardTitle, Chip, Icon, IconButton, Segmented, Slider, Switch, TextField } from "@/components/m3";
import { cn } from "@/lib/cn";

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

export default function PlaygroundPage() {
  const [bearer, setBearer] = React.useState("");
  const [model, setModel] = React.useState(MODELS[0]);
  const [intensityIndex, setIntensityIndex] = React.useState(1);
  const [search, setSearch] = React.useState(false);
  const [codeExec, setCodeExec] = React.useState(false);
  const [systemPrompt, setSystemPrompt] = React.useState("");
  const [messages, setMessages] = React.useState<Message[]>([]);
  const [input, setInput] = React.useState("");
  const [streaming, setStreaming] = React.useState(false);
  const [rawEvents, setRawEvents] = React.useState<string[]>([]);
  const [rawOpen, setRawOpen] = React.useState(false);

  const intensities: Intensity[] = ["fast", "balanced", "deep", "extreme"];
  const intensity = intensities[intensityIndex];

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
            } catch { /* ignore */ }
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
    <AdminShell title="Playground" breadcrumb={["Relay"]}>
      <div className="grid h-[calc(100vh-4rem)] grid-cols-1 gap-0 md:grid-cols-[1fr_360px]">
        <div className="flex min-h-0 flex-col">
          <div className="sticky top-0 z-10 space-y-3 border-b border-outline-variant bg-surface p-4">
            <div className="flex flex-wrap items-center gap-3">
              <div className="flex items-center gap-2">
                <Icon name="neurology" size={18} className="text-on-surface-variant" />
                <select
                  value={model}
                  onChange={(e) => setModel(e.target.value)}
                  className="rounded-m3-xs border border-outline bg-surface px-3 py-2 text-m3-body-m"
                >
                  {MODELS.map((m) => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-m3-label-m text-on-surface-variant">思考强度</span>
                <Segmented
                  value={intensity}
                  onChange={(v) => setIntensityIndex(intensities.indexOf(v as Intensity))}
                  options={intensities.map((i) => ({ value: i, label: i }))}
                />
              </div>
              <Chip selected={search} onClick={() => setSearch((v) => !v)} icon="travel_explore">
                Google Search
              </Chip>
              <Chip selected={codeExec} onClick={() => setCodeExec((v) => !v)} icon="code">
                Code Execution
              </Chip>
            </div>
            <TextField
              label="Authorization bearer"
              placeholder="为空时使用 session — 仅可调 admin token；填入 rk_... 可走客户端路径测试计费"
              value={bearer}
              onChange={(e) => setBearer(e.target.value)}
              variant="filled"
            />
            <TextField
              label="System prompt"
              value={systemPrompt}
              onChange={(e) => setSystemPrompt(e.target.value)}
              variant="filled"
            />
          </div>

          <div className="flex-1 space-y-3 overflow-auto p-4 thin-scroll">
            {messages.length === 0 && (
              <div className="py-20 text-center text-on-surface-variant">
                <Icon name="forum" size={48} className="opacity-40" />
                <div className="mt-3 text-m3-body-m">输入消息开始对话</div>
              </div>
            )}
            {messages.map((m) => (
              <div key={m.id} className={cn("flex", m.role === "user" ? "justify-end" : "justify-start")}>
                <div
                  className={cn(
                    "max-w-[640px] whitespace-pre-wrap rounded-m3-lg px-4 py-3 text-m3-body-m",
                    m.role === "user"
                      ? "rounded-br-m3-xs bg-primary-container text-on-primary-container"
                      : "rounded-bl-m3-xs bg-surface-container text-on-surface",
                  )}
                >
                  {m.thought && m.role === "assistant" && (
                    <details className="mb-2 border-l-2 border-tertiary pl-2 text-m3-body-s italic text-on-surface-variant">
                      <summary className="cursor-pointer text-m3-label-m">
                        💭 Thought · {m.thought.length} chars
                      </summary>
                      <div className="mt-1 whitespace-pre-wrap">{m.thought}</div>
                    </details>
                  )}
                  {m.text || (m.role === "assistant" && streaming ? "…" : "")}
                  {m.finishReason && m.finishReason !== "STOP" && (
                    <div className="mt-2 text-m3-label-m text-on-surface-variant">
                      finishReason: {m.finishReason}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>

          <div className="flex items-end gap-2 border-t border-outline-variant bg-surface-container-low p-4">
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              rows={2}
              placeholder="输入消息，Enter 发送，Shift+Enter 换行"
              className="flex-1 resize-none rounded-m3-md bg-surface-container-high px-3 py-2 text-m3-body-m outline-none"
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  send();
                }
              }}
            />
            <Button icon="send" onClick={send} loading={streaming} disabled={!input.trim()}>
              发送
            </Button>
          </div>
        </div>

        <aside className="hidden border-l border-outline-variant bg-surface-container-low md:flex md:flex-col">
          <div className="border-b border-outline-variant p-4">
            <div className="flex items-center justify-between">
              <div className="text-m3-title-s">Raw SSE</div>
              <IconButton
                icon={rawOpen ? "visibility_off" : "visibility"}
                size="sm"
                onClick={() => setRawOpen((v) => !v)}
              />
            </div>
          </div>
          <div className="flex-1 overflow-auto p-3 thin-scroll">
            {rawOpen ? (
              rawEvents.length === 0 ? (
                <div className="text-m3-body-s text-on-surface-variant">尚未收到事件</div>
              ) : (
                <ul className="space-y-1 font-mono text-m3-body-s">
                  {rawEvents.map((e, i) => (
                    <li key={i} className="truncate">{e}</li>
                  ))}
                </ul>
              )
            ) : (
              <div className="text-m3-body-s text-on-surface-variant">点击眼睛图标查看原始 SSE 事件</div>
            )}
          </div>
        </aside>
      </div>
    </AdminShell>
  );
}
