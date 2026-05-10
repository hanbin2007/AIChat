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
import Accordion from "@mui/material/Accordion";
import AccordionSummary from "@mui/material/AccordionSummary";
import AccordionDetails from "@mui/material/AccordionDetails";
import LinearProgress from "@mui/material/LinearProgress";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import ArrowBackRounded from "@mui/icons-material/ArrowBackRounded";
import ExpandMoreRounded from "@mui/icons-material/ExpandMoreRounded";
import { AppShell } from "@/components/shell/app-shell";
import { Markdown } from "@/components/markdown";
import { getConversation } from "@/lib/store/conversations";

export const dynamic = "force-dynamic";

export default async function ConversationDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const conv = await getConversation(id);
  if (!conv) notFound();

  const modelTotals = new Map<string, number>();
  for (const turn of conv.turns) {
    if (!turn.modelID) continue;
    modelTotals.set(turn.modelID, (modelTotals.get(turn.modelID) ?? 0) + (turn.credits ?? 0));
  }
  const modelMax = Math.max(...modelTotals.values(), 1);

  return (
    <AppShell
      title={conv.title}
      breadcrumb={[
        { label: "AIChat Relay", href: "/dashboard" },
        { label: "请求日志", href: "/requests" },
        { label: "对话详情" },
      ]}
      actions={
        <IconButton
          component={Link}
          href="/requests"
          aria-label="返回请求日志"
        >
          <ArrowBackRounded />
        </IconButton>
      }
    >
      <Stack spacing={3}>
        <Card>
          <CardContent>
            <Stack direction={{ xs: "column", md: "row" }} spacing={2} alignItems="flex-start">
              <Box sx={{ flex: 1 }}>
                <Typography variant="h6" sx={{ fontWeight: 700 }}>
                  {conv.title}
                </Typography>
                <Typography
                  variant="caption"
                  color="text.secondary"
                  sx={{ fontFamily: "var(--font-mono)", display: "block", mt: 0.5 }}
                >
                  {conv.id}
                </Typography>
              </Box>
              <Stack direction="row" spacing={1} flexWrap="wrap">
                {conv.hasErrors ? <Chip size="small" label="包含错误" color="error" /> : null}
                {conv.hasImages ? <Chip size="small" label="图片" /> : null}
                {conv.hasAudio ? <Chip size="small" label="音频" /> : null}
                <Chip
                  size="small"
                  label={conv.confidence === "high" ? "高置信" : "低置信"}
                  variant="outlined"
                />
              </Stack>
            </Stack>
            <Stack
              direction="row"
              spacing={3}
              sx={{ mt: 2, flexWrap: "wrap", color: "text.secondary" }}
            >
              <KV label="账户" value={conv.accountName ?? conv.accountID ?? "—"} />
              <KV label="设备" value={conv.deviceAlias ?? conv.deviceID ?? "—"} />
              <KV
                label="时间"
                value={`${new Date(conv.firstAt).toLocaleString("zh-Hans")} – ${new Date(conv.lastAt).toLocaleString("zh-Hans")}`}
              />
              <KV label="轮次" value={String(conv.turnCount)} />
              <KV
                label="Tokens 入 / 出"
                value={`${conv.totalInputTokens} / ${conv.totalOutputTokens}`}
              />
              <KV label="Credits" value={String(conv.totalCredits)} />
            </Stack>
          </CardContent>
        </Card>

        <Box
          sx={{
            display: "grid",
            gridTemplateColumns: { xs: "1fr", lg: "2fr 1fr" },
            gap: 3,
          }}
        >
          <Stack spacing={2}>
            {conv.turns.map((turn) => (
              <Card key={turn.id} component="article">
                <CardContent>
                  {turn.userText ? (
                    <Stack direction="row" spacing={1.5} sx={{ mb: 2 }}>
                      <Avatar sx={{ bgcolor: "secondary.main", width: 32, height: 32 }}>
                        U
                      </Avatar>
                      <Box sx={{ flex: 1, minWidth: 0 }}>
                        <Typography variant="caption" color="text.secondary">
                          用户
                        </Typography>
                        <Markdown source={turn.userText} />
                      </Box>
                    </Stack>
                  ) : null}

                  {turn.thoughtText ? (
                    <Accordion sx={{ mb: 2, bgcolor: "action.hover" }}>
                      <AccordionSummary expandIcon={<ExpandMoreRounded />}>
                        <Typography variant="caption">
                          💭 思考 · {turn.thoughtText.length} 字符
                        </Typography>
                      </AccordionSummary>
                      <AccordionDetails>
                        <Markdown source={turn.thoughtText} />
                      </AccordionDetails>
                    </Accordion>
                  ) : null}

                  {turn.assistantText ? (
                    <Stack direction="row" spacing={1.5}>
                      <Avatar sx={{ bgcolor: "primary.main", width: 32, height: 32 }}>
                        A
                      </Avatar>
                      <Box sx={{ flex: 1, minWidth: 0 }}>
                        <Typography variant="caption" color="text.secondary">
                          助手
                        </Typography>
                        <Markdown source={turn.assistantText} />
                      </Box>
                    </Stack>
                  ) : null}

                  {turn.error ? (
                    <Box
                      sx={{
                        mt: 2,
                        p: 1.5,
                        borderRadius: 1,
                        border: 1,
                        borderColor: "error.main",
                        color: "error.main",
                        bgcolor: "error.main",
                        bgcolorAlpha: 0.05,
                      }}
                    >
                      <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
                        {turn.error}
                      </Typography>
                    </Box>
                  ) : null}

                  <Stack
                    direction="row"
                    spacing={2}
                    sx={{
                      mt: 2,
                      flexWrap: "wrap",
                      color: "text.secondary",
                      fontSize: "0.75rem",
                    }}
                  >
                    <span>{new Date(turn.timestamp).toLocaleString("zh-Hans")}</span>
                    {turn.modelID ? <span>模型 {turn.modelID}</span> : null}
                    {turn.thinkingIntensity ? <span>强度 {turn.thinkingIntensity}</span> : null}
                    {turn.inputTokens != null ? (
                      <span>
                        Tokens {turn.inputTokens} → {turn.outputTokens ?? 0}
                      </span>
                    ) : null}
                    {turn.credits != null ? <span>{turn.credits} credits</span> : null}
                    {turn.latencyMs != null ? <span>{turn.latencyMs}ms</span> : null}
                    {turn.finishReason ? <span>{turn.finishReason}</span> : null}
                  </Stack>
                </CardContent>
              </Card>
            ))}
          </Stack>

          <Box sx={{ position: { lg: "sticky" }, top: { lg: 24 } }}>
            <Stack spacing={2}>
              <Card>
                <CardHeader title="模型分布" />
                <CardContent>
                  {modelTotals.size === 0 ? (
                    <Typography variant="body2" color="text.secondary">
                      无数据
                    </Typography>
                  ) : (
                    <Stack spacing={1.5}>
                      {Array.from(modelTotals.entries()).map(([m, c]) => (
                        <Box key={m}>
                          <Stack direction="row" justifyContent="space-between" sx={{ mb: 0.5 }}>
                            <Typography
                              variant="body2"
                              sx={{ fontFamily: "var(--font-mono)" }}
                              noWrap
                            >
                              {m}
                            </Typography>
                            <Typography
                              variant="body2"
                              sx={{ fontFamily: "var(--font-mono)" }}
                            >
                              {c}
                            </Typography>
                          </Stack>
                          <LinearProgress variant="determinate" value={(c / modelMax) * 100} />
                        </Box>
                      ))}
                    </Stack>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader title="操作" />
                <CardContent>
                  <Stack spacing={1}>
                    <Button variant="outlined" component={Link} href="/playground">
                      在 Playground 中重放
                    </Button>
                    <Button
                      variant="outlined"
                      component="a"
                      href={`/api/admin/conversations/${conv.id}`}
                      download={`${conv.id}.json`}
                    >
                      导出 JSON
                    </Button>
                  </Stack>
                </CardContent>
              </Card>
            </Stack>
          </Box>
        </Box>
      </Stack>
    </AppShell>
  );
}

function KV({ label, value }: { label: string; value: string }) {
  return (
    <Box>
      <Typography variant="caption" color="text.secondary" sx={{ display: "block" }}>
        {label}
      </Typography>
      <Typography variant="body2" sx={{ fontFamily: "var(--font-mono)" }}>
        {value}
      </Typography>
    </Box>
  );
}
