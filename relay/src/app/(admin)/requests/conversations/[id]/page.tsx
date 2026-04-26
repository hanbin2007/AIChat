"use client";
import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { AdminShell } from "@/components/admin-shell";
import { Badge, Card, CardContent, CardHeader, CardTitle, Icon, IconButton, Switch, Button } from "@/components/m3";
import type { Conversation } from "@/lib/store/conversations";
import { cn } from "@/lib/cn";

export default function ConversationPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const [conversation, setConversation] = React.useState<Conversation | null>(null);
  const [reveal, setReveal] = React.useState(false);

  React.useEffect(() => {
    fetch(`/api/admin/conversations/${params.id}`)
      .then((r) => r.json())
      .then((d) => setConversation(d.conversation));
  }, [params.id]);

  if (!conversation) {
    return (
      <AdminShell title="Conversation">
        <div className="p-6 text-on-surface-variant">加载中…</div>
      </AdminShell>
    );
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
          <IconButton icon="arrow_back" onClick={() => router.back()} aria-label="返回" />
        </div>
      }
    >
      <div className="space-y-4 p-6 pb-24">
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
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_320px]">
          <div className="space-y-4">
            {conversation.turns.map((turn, i) => (
              <article key={turn.id} className="space-y-2">
                {turn.userText && (
                  <Bubble role="user" reveal={reveal}>
                    {turn.userText}
                  </Bubble>
                )}
                {turn.thoughtText && (
                  <ThoughtBlock text={turn.thoughtText} reveal={reveal} />
                )}
                {turn.assistantText && (
                  <Bubble role="assistant" reveal={reveal}>
                    {turn.assistantText}
                  </Bubble>
                )}
                {turn.error && (
                  <Bubble role="error" reveal={true}>
                    {turn.error}
                  </Bubble>
                )}
                <div className="ml-1 flex flex-wrap items-center gap-2 text-m3-label-s text-on-surface-variant">
                  <span>{new Date(turn.timestamp).toLocaleTimeString()}</span>
                  <span>·</span>
                  <span>{turn.modelID ?? "—"}</span>
                  {turn.thinkingIntensity && (
                    <>
                      <span>·</span>
                      <span>{turn.thinkingIntensity}</span>
                    </>
                  )}
                  <span>·</span>
                  <span>{turn.inputTokens ?? 0}→{turn.outputTokens ?? 0} tokens</span>
                  <span>·</span>
                  <span>{turn.credits ?? 0} credits</span>
                  <span>·</span>
                  <span>{turn.latencyMs ?? 0}ms</span>
                  {turn.finishReason && (
                    <>
                      <span>·</span>
                      <span>{turn.finishReason}</span>
                    </>
                  )}
                  {i < conversation.turns.length - 1 && (
                    <span className="mx-2 h-px flex-1 bg-outline-variant" />
                  )}
                </div>
              </article>
            ))}
          </div>

          <aside className="space-y-3 lg:sticky lg:top-20 self-start">
            <Card variant="filled" className="p-4">
              <div className="text-m3-label-m text-on-surface-variant">Model breakdown</div>
              <ul className="mt-2 space-y-2 text-m3-body-s">
                {Array.from(modelBreakdown.entries()).map(([m, credits]) => {
                  const total = conversation.totalCredits || 1;
                  return (
                    <li key={m}>
                      <div className="flex justify-between">
                        <span>{m}</span>
                        <span className="text-on-surface-variant">{formatNumber(credits)}</span>
                      </div>
                      <div className="mt-1 h-1 rounded-full bg-surface-container-highest">
                        <div
                          className="h-1 rounded-full bg-primary"
                          style={{ width: `${Math.round((credits / total) * 100)}%` }}
                        />
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Card>
            <Card variant="filled" className="p-4">
              <div className="text-m3-label-m text-on-surface-variant">操作</div>
              <div className="mt-3 flex flex-col gap-2">
                <Button variant="outlined" icon="replay">Replay in Playground</Button>
                <Button variant="outlined" icon="download">Export JSON</Button>
                <Button variant="outlined" icon="flag">Flag for review</Button>
              </div>
            </Card>
          </aside>
        </div>
      </div>
    </AdminShell>
  );
}

function Bubble({
  role,
  reveal,
  children,
}: {
  role: "user" | "assistant" | "error";
  reveal: boolean;
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
        )}
      >
        {content}
      </div>
    </div>
  );
}

function ThoughtBlock({ text, reveal }: { text: string; reveal: boolean }) {
  const [open, setOpen] = React.useState(false);
  return (
    <div className="flex justify-start">
      <div className="max-w-[640px] rounded-m3-md border-l-2 border-tertiary bg-surface-container-lowest px-3 py-2 text-m3-body-s text-on-surface-variant">
        <button
          onClick={() => setOpen((v) => !v)}
          className="flex items-center gap-1 text-m3-label-m"
        >
          <Icon name={open ? "expand_less" : "expand_more"} size={16} />
          💭 Thought · {text.length.toLocaleString()} chars
        </button>
        {open && (
          <div className="mt-2 whitespace-pre-wrap italic">
            {reveal ? text : redactHints(text)}
          </div>
        )}
      </div>
    </div>
  );
}

function redactHints(text: React.ReactNode): string {
  const str = typeof text === "string" ? text : "";
  const chars = str.length;
  return `[${chars.toLocaleString()} chars redacted — click Reveal to show]`;
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
