"use client";
import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import Box from "@mui/material/Box";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import Chip from "@mui/material/Chip";
import Switch from "@mui/material/Switch";
import FormControlLabel from "@mui/material/FormControlLabel";
import IconButton from "@mui/material/IconButton";
import Tooltip from "@mui/material/Tooltip";
import Button from "@mui/material/Button";
import LinearProgress from "@mui/material/LinearProgress";
import Grid from "@mui/material/Grid2";
import Accordion from "@mui/material/Accordion";
import AccordionSummary from "@mui/material/AccordionSummary";
import AccordionDetails from "@mui/material/AccordionDetails";
import Divider from "@mui/material/Divider";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import ReplayIcon from "@mui/icons-material/Replay";
import DownloadIcon from "@mui/icons-material/Download";
import FlagIcon from "@mui/icons-material/Flag";
import { AppShell } from "@/components/shell/app-shell";
import type { Conversation } from "@/lib/store/conversations";

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
      <AppShell title="Conversation">
        <Box sx={{ p: 3, color: "text.secondary" }}>加载中…</Box>
      </AppShell>
    );
  }

  const modelBreakdown = new Map<string, number>();
  for (const t of conversation.turns) {
    if (!t.modelID) continue;
    modelBreakdown.set(t.modelID, (modelBreakdown.get(t.modelID) ?? 0) + (t.credits ?? 0));
  }

  return (
    <AppShell
      title={conversation.title}
      breadcrumb={["Relay", "Requests", "Conversations"]}
      actions={
        <Stack direction="row" spacing={1} alignItems="center">
          <FormControlLabel
            control={<Switch checked={reveal} onChange={() => setReveal((v) => !v)} />}
            label="Reveal"
          />
          <Tooltip title="返回">
            <IconButton onClick={() => router.back()} aria-label="返回">
              <ArrowBackIcon />
            </IconButton>
          </Tooltip>
        </Stack>
      }
    >
      <Box sx={{ p: 3, pb: 12 }}>
        <Stack spacing={2}>
          <Card sx={{ boxShadow: 1 }}>
            <CardHeader title="会话概览" titleTypographyProps={{ variant: "subtitle1" }} />
            <CardContent>
              <Stack direction="row" spacing={3} flexWrap="wrap" useFlexGap>
                <Stat label="Turns" value={conversation.turnCount.toString()} />
                <Stat
                  label="Tokens in / out"
                  value={`${formatNumber(conversation.totalInputTokens)} / ${formatNumber(conversation.totalOutputTokens)}`}
                />
                <Stat label="Credits" value={formatNumber(conversation.totalCredits)} />
                <Stat label="Models" value={conversation.modelsUsed.join(", ")} />
                <Stat
                  label="Device"
                  value={`${conversation.devicePlatform ?? "?"} · ${conversation.deviceID?.slice(0, 10) ?? "—"}`}
                />
                <Stat
                  label="Range"
                  value={`${new Date(conversation.firstAt).toLocaleString()} → ${new Date(conversation.lastAt).toLocaleString()}`}
                />
                {conversation.hasErrors && <Chip color="error" label="has errors" />}
                {conversation.confidence === "low" && <Chip color="warning" label="推断归属" />}
              </Stack>
            </CardContent>
          </Card>

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, lg: 8 }}>
              <Stack spacing={2}>
                {conversation.turns.map((turn, i) => (
                  <Box component="article" key={turn.id}>
                    <Stack spacing={1}>
                      {turn.userText && (
                        <Bubble role="user" reveal={reveal}>
                          {turn.userText}
                        </Bubble>
                      )}
                      {turn.thoughtText && <ThoughtBlock text={turn.thoughtText} reveal={reveal} />}
                      {turn.assistantText && (
                        <Bubble role="assistant" reveal={reveal}>
                          {turn.assistantText}
                        </Bubble>
                      )}
                      {turn.error && (
                        <Bubble role="error" reveal>
                          {turn.error}
                        </Bubble>
                      )}
                      <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap alignItems="center" sx={{ ml: 1 }}>
                        <Typography variant="caption" sx={{ color: "text.secondary" }}>
                          {new Date(turn.timestamp).toLocaleTimeString()}
                        </Typography>
                        <DotSep />
                        <Typography variant="caption" sx={{ color: "text.secondary" }}>
                          {turn.modelID ?? "—"}
                        </Typography>
                        {turn.thinkingIntensity && (
                          <>
                            <DotSep />
                            <Typography variant="caption" sx={{ color: "text.secondary" }}>
                              {turn.thinkingIntensity}
                            </Typography>
                          </>
                        )}
                        <DotSep />
                        <Typography variant="caption" sx={{ color: "text.secondary" }}>
                          {turn.inputTokens ?? 0}→{turn.outputTokens ?? 0} tokens
                        </Typography>
                        <DotSep />
                        <Typography variant="caption" sx={{ color: "text.secondary" }}>
                          {turn.credits ?? 0} credits
                        </Typography>
                        <DotSep />
                        <Typography variant="caption" sx={{ color: "text.secondary" }}>
                          {turn.latencyMs ?? 0}ms
                        </Typography>
                        {turn.finishReason && (
                          <>
                            <DotSep />
                            <Typography variant="caption" sx={{ color: "text.secondary" }}>
                              {turn.finishReason}
                            </Typography>
                          </>
                        )}
                      </Stack>
                      {i < conversation.turns.length - 1 && <Divider sx={{ mt: 2 }} />}
                    </Stack>
                  </Box>
                ))}
              </Stack>
            </Grid>

            <Grid size={{ xs: 12, lg: 4 }}>
              <Box sx={{ position: { lg: "sticky" }, top: { lg: 80 } }}>
                <Stack spacing={2}>
                  <Card sx={{ bgcolor: "action.hover" }}>
                    <CardContent>
                      <Typography variant="caption" sx={{ color: "text.secondary" }}>
                        Model breakdown
                      </Typography>
                      <Stack spacing={1.5} sx={{ mt: 1 }}>
                        {Array.from(modelBreakdown.entries()).map(([m, credits]) => {
                          const total = conversation.totalCredits || 1;
                          const pct = Math.round((credits / total) * 100);
                          return (
                            <Box key={m}>
                              <Stack direction="row" justifyContent="space-between">
                                <Typography variant="body2">{m}</Typography>
                                <Typography variant="body2" sx={{ color: "text.secondary" }}>
                                  {formatNumber(credits)}
                                </Typography>
                              </Stack>
                              <LinearProgress
                                variant="determinate"
                                value={pct}
                                sx={{ mt: 0.5, height: 4, borderRadius: 2 }}
                              />
                            </Box>
                          );
                        })}
                      </Stack>
                    </CardContent>
                  </Card>
                  <Card sx={{ bgcolor: "action.hover" }}>
                    <CardContent>
                      <Typography variant="caption" sx={{ color: "text.secondary" }}>
                        操作
                      </Typography>
                      <Stack spacing={1} sx={{ mt: 1.5 }}>
                        <Button variant="outlined" startIcon={<ReplayIcon />}>
                          Replay in Playground
                        </Button>
                        <Button variant="outlined" startIcon={<DownloadIcon />}>
                          Export JSON
                        </Button>
                        <Button variant="outlined" startIcon={<FlagIcon />}>
                          Flag for review
                        </Button>
                      </Stack>
                    </CardContent>
                  </Card>
                </Stack>
              </Box>
            </Grid>
          </Grid>
        </Stack>
      </Box>
    </AppShell>
  );
}

function DotSep() {
  return (
    <Typography variant="caption" sx={{ color: "text.disabled" }}>
      ·
    </Typography>
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
  const content = reveal
    ? children
    : typeof children === "string"
      ? redactHints(children)
      : children;
  const bg =
    role === "user"
      ? "primary.main"
      : role === "error"
        ? "error.light"
        : "action.hover";
  const fg =
    role === "user"
      ? "primary.contrastText"
      : role === "error"
        ? "error.contrastText"
        : "text.primary";
  return (
    <Box sx={{ display: "flex", justifyContent: role === "user" ? "flex-end" : "flex-start" }}>
      <Box
        sx={{
          maxWidth: 640,
          whiteSpace: "pre-wrap",
          px: 2,
          py: 1.5,
          borderRadius: 2,
          bgcolor: bg,
          color: fg,
          borderBottomRightRadius: role === "user" ? 4 : 16,
          borderBottomLeftRadius: role === "user" ? 16 : 4,
        }}
      >
        {content}
      </Box>
    </Box>
  );
}

function ThoughtBlock({ text, reveal }: { text: string; reveal: boolean }) {
  return (
    <Box sx={{ display: "flex", justifyContent: "flex-start" }}>
      <Accordion
        disableGutters
        elevation={0}
        sx={{
          maxWidth: 640,
          width: "100%",
          bgcolor: "background.paper",
          borderLeft: 2,
          borderColor: "secondary.main",
          borderRadius: 2,
          "&:before": { display: "none" },
        }}
      >
        <AccordionSummary expandIcon={<ExpandMoreIcon fontSize="small" />} sx={{ minHeight: 0 }}>
          <Typography variant="caption" sx={{ color: "text.secondary" }}>
            💭 Thought · {text.length.toLocaleString()} chars
          </Typography>
        </AccordionSummary>
        <AccordionDetails>
          <Typography
            variant="caption"
            component="div"
            sx={{ whiteSpace: "pre-wrap", fontStyle: "italic", color: "text.secondary" }}
          >
            {reveal ? text : redactHints(text)}
          </Typography>
        </AccordionDetails>
      </Accordion>
    </Box>
  );
}

function redactHints(text: React.ReactNode): string {
  const str = typeof text === "string" ? text : "";
  const chars = str.length;
  return `[${chars.toLocaleString()} chars redacted — click Reveal to show]`;
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <Box>
      <Typography variant="caption" sx={{ color: "text.secondary" }}>
        {label}
      </Typography>
      <Typography variant="subtitle2" sx={{ mt: 0.25 }}>
        {value}
      </Typography>
    </Box>
  );
}

function formatNumber(n: number): string {
  if (n > 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n > 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toLocaleString();
}
