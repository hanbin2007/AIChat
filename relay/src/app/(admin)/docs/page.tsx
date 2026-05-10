"use client";
import * as React from "react";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import Link from "@mui/material/Link";
import { AppShell } from "@/components/shell/app-shell";

type Lang = "curl" | "swift" | "node";

const ENDPOINTS = [
  {
    id: "health",
    title: "GET /api/health",
    description: "机器可读的健康检查。",
    request: "curl http://localhost:8787/api/health",
  },
  {
    id: "catalog",
    title: "GET /api/v1/billing/catalog",
    description: "返回所有可售套餐 + 计价策略。公开，无需鉴权。",
    request: "curl http://localhost:8787/api/v1/billing/catalog",
  },
  {
    id: "status",
    title: "GET /api/v1/account/status",
    description: "返回当前 client key 对应的账户 + device + grants + 最近用量。",
    request: `curl http://localhost:8787/api/v1/account/status \\
  -H 'Authorization: Bearer rk_xxxxx'`,
  },
  {
    id: "chat",
    title: "POST /api/v1/chat/stream",
    description:
      "SSE 流式对话端点。接受与 Swift relay 完全相同的请求体（messages[]、thinkingIntensity、systemPrompt 等）。",
    request: `curl -N http://localhost:8787/api/v1/chat/stream \\
  -H 'Authorization: Bearer <token>' \\
  -H 'Content-Type: application/json' \\
  -d '{
    "model": "gemini-3-flash-preview",
    "thinkingIntensity": "balanced",
    "messages": [{ "role": "user", "text": "你好" }]
  }'`,
  },
  {
    id: "transcribe",
    title: "POST /api/v1/audio/transcribe",
    description: "上传音频 base64 → Gemini 转写文本。非流式。",
    request: `curl http://localhost:8787/api/v1/audio/transcribe \\
  -H 'Authorization: Bearer <token>' \\
  -H 'Content-Type: application/json' \\
  -d '{ "model": "gemini-3-flash-preview", "audio": { "mimeType": "audio/m4a", "base64Data": "..." } }'`,
  },
  {
    id: "memory",
    title: "POST /api/v1/memory/extract",
    description: "从对话抽取结构化记忆（JSON）。非流式。",
    request: `# see schema in v0.3 docs`,
  },
  {
    id: "bootstrap",
    title: "POST /api/v1/activation/bootstrap",
    description: "设备首次激活：创建试用账户 + 签发 client key。",
    request: `curl http://localhost:8787/api/v1/activation/bootstrap \\
  -d '{ "deviceID": "<uuid>", "platform": "watch" }'`,
  },
  {
    id: "offline",
    title: "POST /api/v1/offline/exchange",
    description: "使用离线激活码绑定设备。",
    request: `curl http://localhost:8787/api/v1/offline/exchange \\
  -d '{ "activationCode": "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", "deviceID": "<uuid>", "platform": "watch" }'`,
  },
];

const codeBlockSx = {
  mt: 1.5,
  bgcolor: "action.hover",
  borderRadius: 2,
  p: 2,
  fontFamily: "monospace",
  fontSize: "0.8125rem",
  whiteSpace: "pre",
  overflow: "auto",
} as const;

export default function DocsPage() {
  const [lang, setLang] = React.useState<Lang>("curl");
  return (
    <AppShell title="API Docs" breadcrumb={["System"]}>
      <Box sx={{ p: 3, display: "grid", gap: 3, gridTemplateColumns: { xs: "1fr", lg: "220px 1fr" } }}>
        <Box component="aside" sx={{ position: { lg: "sticky" }, top: { lg: 80 }, alignSelf: "start" }}>
          <Stack spacing={0.5}>
            {ENDPOINTS.map((e) => (
              <Link
                key={e.id}
                href={`#${e.id}`}
                underline="hover"
                color="inherit"
                sx={{ px: 1.5, py: 1, borderRadius: 1, fontSize: "0.875rem" }}
              >
                {e.title}
              </Link>
            ))}
            <Link
              href="#xcconfig"
              underline="hover"
              color="inherit"
              sx={{ px: 1.5, py: 1, borderRadius: 1, fontSize: "0.875rem", fontWeight: 500 }}
            >
              把 Watch 切到此 relay
            </Link>
          </Stack>
        </Box>
        <Stack spacing={3}>
          <Card id="xcconfig" sx={{ bgcolor: "action.hover" }}>
            <CardContent>
              <Typography variant="h6">把 Watch 客户端切到此 relay</Typography>
              <Typography variant="body2" sx={{ mt: 1, color: "text.secondary" }}>
                打开{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  Config/Secrets.xcconfig
                </Typography>
                ，把下面这段原样贴进去（注意 xcconfig 中{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  //
                </Typography>{" "}
                会被当注释，所以 URL 用{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  /$()/
                </Typography>
                ）：
              </Typography>
              <Box component="pre" sx={codeBlockSx}>
{`AI_BACKEND_MODE      = relay
AI_RELAY_BASE_URL    = http:/$()/127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = <RELAY_BEARER_TOKEN>
GEMINI_MODEL         = gemini-3-flash-preview`}
              </Box>
            </CardContent>
          </Card>

          <Tabs value={lang} onChange={(_, v) => setLang(v as Lang)}>
            <Tab value="curl" label="curl" />
            <Tab value="swift" label="Swift" />
            <Tab value="node" label="Node" />
          </Tabs>
          {ENDPOINTS.map((e) => (
            <Card key={e.id} id={e.id} sx={{ scrollMarginTop: 96 }}>
              <CardContent>
                <Typography variant="h6">{e.title}</Typography>
                <Typography variant="body2" sx={{ mt: 0.5, color: "text.secondary" }}>
                  {e.description}
                </Typography>
                <Box component="pre" sx={codeBlockSx}>
                  {e.request}
                </Box>
              </CardContent>
            </Card>
          ))}
        </Stack>
      </Box>
    </AppShell>
  );
}
