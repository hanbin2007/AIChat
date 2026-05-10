import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import { Stack } from "@/components/lib/stack";
import Typography from "@mui/material/Typography";
import Chip from "@mui/material/Chip";
interface Endpoint {
  method: string;
  path: string;
  title: string;
  description: string;
}

const ENDPOINTS: Endpoint[] = [
  {
    method: "GET",
    path: "/api/health",
    title: "健康检查",
    description: "返回 { ok: true } 表示进程在线。供负载均衡探活。",
  },
  {
    method: "GET",
    path: "/api/v1/billing/catalog",
    title: "套餐目录",
    description: "获取当前可购买的订阅套餐与按次充值产品。",
  },
  {
    method: "POST",
    path: "/api/v1/account/status",
    title: "账户状态",
    description: "客户端使用 client key 查询自身账户、剩余额度、最近用量。",
  },
  {
    method: "POST",
    path: "/api/v1/chat/stream",
    title: "聊天 SSE 流",
    description: "主聊天接口，返回 answer_delta / thought_delta / done / error 事件。",
  },
  {
    method: "POST",
    path: "/api/v1/audio/transcribe",
    title: "语音转写",
    description: "上传音频，得到识别后的文字。",
  },
  {
    method: "POST",
    path: "/api/v1/memory/extract",
    title: "记忆抽取",
    description: "从对话上下文中提炼用户长期记忆。",
  },
  {
    method: "GET",
    path: "/api/v1/activation/bootstrap",
    title: "激活引导",
    description: "客户端首次启动时获取激活策略与公共配置。",
  },
  {
    method: "POST",
    path: "/api/v1/offline/exchange",
    title: "离线激活兑换",
    description: "用激活码兑换 client key（无需联网账户体系）。",
  },
];

const XCCONFIG = `// AIChat 客户端 — Config/Secrets.xcconfig
AI_BACKEND_MODE = relay
RELAY_BASE_URL = http:/$()/<your-relay-host>:8787
RELAY_BEARER_TOKEN = <在 .env 中配置的 RELAY_BEARER_TOKEN>`;

export default function DocsPage() {
  return (
    <>
      <Box
        sx={{
          display: "grid",
          gridTemplateColumns: { xs: "1fr", lg: "240px 1fr" },
          gap: 3,
        }}
      >
        <Box
          sx={{
            display: { xs: "none", lg: "block" },
            position: "sticky",
            top: 24,
            alignSelf: "start",
          }}
        >
          <Card variant="outlined">
            <CardContent>
              <Typography variant="overline" color="text.secondary">
                目录
              </Typography>
              <Stack spacing={0.5} sx={{ mt: 1 }}>
                {ENDPOINTS.map((e) => (
                  <Typography
                    key={e.path}
                    variant="body2"
                    component="a"
                    href={`#${e.path}`}
                    sx={{ color: "primary.main", textDecoration: "none" }}
                  >
                    {e.title}
                  </Typography>
                ))}
              </Stack>
            </CardContent>
          </Card>
        </Box>

        <Stack spacing={2}>
          <Card sx={{ bgcolor: "action.hover" }}>
            <CardHeader
              title={
                <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                  Watch 客户端 xcconfig 片段
                </Typography>
              }
            />
            <CardContent>
              <Box
                component="pre"
                sx={{
                  fontFamily: "var(--font-mono)",
                  fontSize: "0.8125rem",
                  m: 0,
                  whiteSpace: "pre-wrap",
                }}
              >
                {XCCONFIG}
              </Box>
            </CardContent>
          </Card>

          {ENDPOINTS.map((e) => (
            <Card key={e.path} id={e.path}>
              <CardContent>
                <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                  <Chip
                    size="small"
                    label={e.method}
                    color={e.method === "GET" ? "info" : "primary"}
                  />
                  <Typography
                    variant="subtitle1"
                    sx={{ fontFamily: "var(--font-mono)", fontWeight: 700 }}
                  >
                    {e.path}
                  </Typography>
                </Stack>
                <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 0.5 }}>
                  {e.title}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {e.description}
                </Typography>
              </CardContent>
            </Card>
          ))}
        </Stack>
      </Box>
    </>
  );
}
