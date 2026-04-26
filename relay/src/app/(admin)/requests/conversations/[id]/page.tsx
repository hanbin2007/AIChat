"use client";
import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Card, CardContent, CardHeader, CardTitle, Icon, IconButton, Segmented, Switch, Button, useSnackbar } from "@/components/m3";
import type { Conversation } from "@/lib/store/conversations";
import { cn } from "@/lib/cn";

type Speed = "1" | "2" | "4" | "8";

export default function ConversationPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const snack = useSnackbar();
  const [conversation, setConversation] = React.useState<Conversation | null>(null);
  const [reveal, setReveal] = React.useState(false);

  // Playback state.
  const [playback, setPlayback] = React.useState<{
    active: boolean;
    speed: Speed;
    current: { turnId: string; thought: string; answer: string } | null;
    completed: Set<string>;
  }>({ active: false, speed: "1", current: null, completed: new Set() });
  const playbackAbort = React.useRef<AbortController | null>(null);

  async function refresh() {
    const res = await fetch(`/api/admin/conversations/${params.id}`);
    if (res.ok) setConversation((await res.json()).conversation);
  }
  React.useEffect(() => { refresh(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [params.id]);

  React.useEffect(() => () => playbackAbort.current?.abort(), []);

  React.useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.code === "Space") {
        e.preventDefault();
        playback.active ? stopPlayback() : startPlayback();
      }
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
    /* eslint-disable-next-line react-hooks/exhaustive-deps */
  }, [playback.active]);

  if (!conversation) {
    return (
      <AdminShell title="Conversation">
        <div className="p-6 text-on-surface-variant">加载中…</div>
      </AdminShell>
    );
  }

  async function togglePin() {
    if (!conversation) return;
    const next = !conversation.pinned;
    await fetch(`/api/admin/conversations/${conversation.id}/pin`, {
      method: next ? "POST" : "DELETE",
    });
    snack.push({ message: next ? "已置顶（豁免日志清理）" : "已取消置顶" });
    refresh();
  }

  function exportAs(format: "json" | "markdown" | "transcript") {
    if (!conversation) return;
    window.location.href = `/api/admin/conversations/${conversation.id}/export?format=${format}`;
  }

  async function startPlayback() {
    if (!conversation) return;
    playbackAbort.current?.abort();
    const ctl = new AbortController();
    playbackAbort.current = ctl;
    setPlayback((p) => ({ ...p, active: true, current: null, completed: new Set() }));

    const res = await fetch(
      `/api/admin/conversations/${conversation.id}/replay?speed=${playback.speed}`,
      { signal: ctl.signal },
    );
    if (!res.ok || !res.body) {
      snack.push({ message: "回放启动失败" });
      setPlayback((p) => ({ ...p, active: false }));
      return;
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffered = "";
    let currentEvent = "";
    type CurrentTurn = { turnId: string; thought: string; answer: string };
    let currentTurn: CurrentTurn | null = null;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffered += decoder.decode(value, { stream: true });
        const lines = buffered.split("\n");
        buffered = lines.pop() ?? "";
        for (const line of lines) {
          if (line.startsWith("event:")) currentEvent = line.slice(6).trim();
          else if (line.startsWith("data:")) {
            const data = line.slice(5).trim();
            if (!data) continue;
            try {
              const parsed = JSON.parse(data);
              if (currentEvent === "turn_start") {
                currentTurn = { turnId: parsed.turnId, thought: "", answer: "" };
                setPlayback((p) => ({ ...p, current: currentTurn }));
              } else if (currentEvent === "thought_delta" && currentTurn) {
                const ct: CurrentTurn = currentTurn;
                currentTurn = { ...ct, thought: ct.thought + parsed.text };
                setPlayback((p) => ({ ...p, current: currentTurn }));
              } else if (currentEvent === "answer_delta" && currentTurn) {
                const ct: CurrentTurn = currentTurn;
                currentTurn = { ...ct, answer: ct.answer + parsed.text };
                setPlayback((p) => ({ ...p, current: currentTurn }));
              } else if (currentEvent === "turn_end" && currentTurn) {
                const id = currentTurn.turnId;
                setPlayback((p) => {
                  const completed = new Set(p.completed);
                  completed.add(id);
                  return { ...p, completed };
                });
                currentTurn = null;
              } else if (currentEvent === "conversation_end") {
                setPlayback((p) => ({ ...p, active: false, current: null }));
              }
            } catch { /* ignore */ }
          }
        }
      }
    } catch {
      // Aborted or network error.
    } finally {
      setPlayback((p) => ({ ...p, active: false }));
    }
  }

  function stopPlayback() {
    playbackAbort.current?.abort();
    setPlayback((p) => ({ ...p, active: false, current: null }));
  }

  const modelBreakdown = new Map<string, number>();
  for (const t of conversation.turns) {
    if (!t.modelID) continue;
    modelBreakdown.set(t.modelID, (modelBreakdown.get(t.modelID) ?? 0) + (t.credits ?? 0));
  }

  return (
    <AdminShell
      title={conversation.title}
      breadcrumb={["Relay", "Requests", "Conversations"]}
      actions={
        <div className="flex items-center gap-2">
          <Switch checked={reveal} onChange={() => setReveal((v) => !v)} label="Reveal" />
          <IconButton
            icon={conversation.pinned ? "push_pin" : "keep"}
            filled={conversation.pinned}
            onClick={togglePin}
            aria-label={conversation.pinned ? "取消置顶" : "置顶"}
          />
          <IconButton icon="arrow_back" onClick={() => router.back()} aria-label="返回" />
        </div>
      }
    >
      <div className="space-y-4 p-6 pb-32">
        <Card variant="elevated">
          <CardHeader>
            <CardTitle>会话概览</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-6">
            <Stat label="Turns" value={conversation.turnCount.toString()} />
            <Stat label="Tokens in / out" value={`${formatNumber(conversation.totalInputTokens)} / ${formatNumber(conversation.totalOutputTokens)}`} />
            <Stat label="Credits" value={formatNumber(conversation.totalCredits)} />
            <Stat label="Models" value={conversation.modelsUsed.join(", ")} />
            <Stat label="Device" value={`${conversation.devicePlatform ?? "?"} · ${conversation.deviceID?.slice(0, 10) ?? "—"}`} />
            <Stat label="Range" value={`${new Date(conversation.firstAt).toLocaleString()} → ${new Date(conversation.lastAt).toLocaleString()}`} />
            {conversation.hasErrors && <Badge tone="error">has errors</Badge>}
            {conversation.confidence === "low" && <Badge tone="warn">推断归属</Badge>}
            {conversation.pinned && <Badge tone="info">📌 置顶</Badge>}
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_320px]">
          <div className="space-y-4">
            {conversation.turns.map((turn, i) => {
              const isCurrent = playback.active && playback.current?.turnId === turn.id;
              const isComplete = playback.completed.has(turn.id);
              const isPlaybackPending = playback.active && !isCurrent && !isComplete;
              return (
                <article key={turn.id} className={cn("space-y-2 transition-opacity", isPlaybackPending && "opacity-30")}>
                  {turn.userText && (
                    <Bubble role="user" reveal={reveal}>{turn.userText}</Bubble>
                  )}
                  {(isCurrent ? playback.current!.thought : turn.thoughtText) && (
                    <ThoughtBlock text={isCurrent ? playback.current!.thought : turn.thoughtText!} reveal={reveal} live={isCurrent} />
                  )}
                  {(isCurrent ? playback.current!.answer : turn.assistantText) && (
                    <Bubble role="assistant" reveal={reveal} live={isCurrent}>
                      {isCurrent ? playback.current!.answer : turn.assistantText!}
                    </Bubble>
                  )}
                  {turn.error && <Bubble role="error" reveal={true}>{turn.error}</Bubble>}
                  <div className="ml-1 flex flex-wrap items-center gap-2 text-m3-label-s text-on-surface-variant">
                    <span>{new Date(turn.timestamp).toLocaleTimeString()}</span>
                    <span>·</span>
                    <span>{turn.modelID ?? "—"}</span>
                    {turn.thinkingIntensity && (<><span>·</span><span>{turn.thinkingIntensity}</span></>)}
                    <span>·</span><span>{turn.inputTokens ?? 0}→{turn.outputTokens ?? 0} tokens</span>
                    <span>·</span><span>{turn.credits ?? 0} credits</span>
                    <span>·</span><span>{turn.latencyMs ?? 0}ms</span>
                    {turn.finishReason && (<><span>·</span><span>{turn.finishReason}</span></>)}
                    {i < conversation.turns.length - 1 && <span className="mx-2 h-px flex-1 bg-outline-variant" />}
                  </div>
                </article>
              );
            })}
          </div>

          <aside className="space-y-3 lg:sticky lg:top-20 self-start">
            <Card variant="filled" className="p-4">
              <div className="text-m3-label-m text-on-surface-variant">Model breakdown</div>
              <ul className="mt-2 space-y-2 text-m3-body-s">
                {Array.from(modelBreakdown.entries()).map(([m, credits]) => {
                  const total = conversation.totalCredits || 1;
                  return (
                    <li key={m}>
                      <div className="flex justify-between"><span>{m}</span><span className="text-on-surface-variant">{formatNumber(credits)}</span></div>
                      <div className="mt-1 h-1 rounded-full bg-surface-container-highest">
                        <div className="h-1 rounded-full bg-primary" style={{ width: `${Math.round((credits / total) * 100)}%` }} />
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Card>
            <Card variant="filled" className="p-4">
              <div className="text-m3-label-m text-on-surface-variant">导出</div>
              <div className="mt-3 flex flex-col gap-2">
                <Button variant="outlined" icon="data_object" onClick={() => exportAs("json")}>Export JSON</Button>
                <Button variant="outlined" icon="article" onClick={() => exportAs("markdown")}>Export Markdown</Button>
                <Button variant="outlined" icon="text_snippet" onClick={() => exportAs("transcript")}>Plain transcript</Button>
              </div>
            </Card>
          </aside>
        </div>
      </div>

      {/* Playback bar — pinned to bottom. Space toggles play. */}
      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-outline-variant bg-surface-container-low/95 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center gap-3 px-6 py-3">
          <IconButton
            icon={playback.active ? "stop" : "play_arrow"}
            filled
            variant="filled"
            onClick={playback.active ? stopPlayback : startPlayback}
            aria-label={playback.active ? "停止" : "播放"}
          />
          <span className="text-m3-label-l text-on-surface-variant">速度</span>
          <Segmented
            value={playback.speed}
            onChange={(v) => setPlayback((p) => ({ ...p, speed: v }))}
            options={[
              { value: "1", label: "1×" },
              { value: "2", label: "2×" },
              { value: "4", label: "4×" },
              { value: "8", label: "8×" },
            ]}
          />
          <div className="flex-1 text-right text-m3-body-s text-on-surface-variant">
            {playback.active
              ? `回放中 · ${playback.completed.size}/${conversation.turnCount} turns`
              : `Space 播放 · ${conversation.turnCount} turns`}
          </div>
        </div>
      </div>
    </AdminShell>
  );
}

function Bubble({
  role,
  reveal,
  live,
  children,
}: {
  role: "user" | "assistant" | "error";
  reveal: boolean;
  live?: boolean;
  children: React.ReactNode;
}) {
  const content = reveal ? children : typeof children === "string" ? redactHints(children) : children;
  return (
    <div className={cn("flex", role === "user" ? "justify-end" : "justify-start")}>
      <div
        className={cn(
          "max-w-[640px] whitespace-pre-wrap rounded-m3-lg px-4 py-3 text-m3-body-m",
          role === "user" && "rounded-br-m3-xs bg-primary-container text-on-primary-container",
          role === "assistant" && "rounded-bl-m3-xs bg-surface-container text-on-surface",
          role === "error" && "rounded-bl-m3-xs bg-error-container text-on-error-container",
          live && "ring-2 ring-primary/40",
        )}
      >
        {content}
        {live && <span className="ml-1 inline-block h-3 w-1 animate-pulse bg-primary" />}
      </div>
    </div>
  );
}

function ThoughtBlock({ text, reveal, live }: { text: string; reveal: boolean; live?: boolean }) {
  const [open, setOpen] = React.useState(false);
  React.useEffect(() => {
    if (live) setOpen(true);
  }, [live]);
  return (
    <div className="flex justify-start">
      <div className={cn(
        "max-w-[640px] rounded-m3-md border-l-2 border-tertiary bg-surface-container-lowest px-3 py-2 text-m3-body-s text-on-surface-variant",
        live && "ring-1 ring-tertiary/40",
      )}>
        <button onClick={() => setOpen((v) => !v)} className="flex items-center gap-1 text-m3-label-m">
          <Icon name={open ? "expand_less" : "expand_more"} size={16} />
          💭 Thought · {text.length.toLocaleString()} chars
        </button>
        {open && <div className="mt-2 whitespace-pre-wrap italic">{reveal ? text : redactHints(text)}</div>}
      </div>
    </div>
  );
}

function redactHints(text: React.ReactNode): string {
  const str = typeof text === "string" ? text : "";
  return `[${str.length.toLocaleString()} chars redacted — click Reveal to show]`;
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-m3-label-m text-on-surface-variant">{label}</div>
      <div className="mt-1 text-m3-title-s text-on-surface">{value}</div>
    </div>
  );
}

function formatNumber(n: number): string {
  if (n > 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n > 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toLocaleString();
}
