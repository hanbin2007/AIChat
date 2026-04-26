"use client";
import * as React from "react";
import { AdminShell } from "@/components/admin-shell";
import { Card, CardContent, CardHeader, CardTitle, Tabs } from "@/components/m3";

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
    description: "SSE 流式对话端点。接受与 Swift relay 完全相同的请求体（messages[]、thinkingIntensity、systemPrompt 等）。",
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

export default function DocsPage() {
  const [lang, setLang] = React.useState<Lang>("curl");
  return (
    <AdminShell title="API Docs" breadcrumb={["System"]}>
      <div className="grid gap-4 p-6 lg:grid-cols-[220px_1fr]">
        <aside className="space-y-1 lg:sticky lg:top-20 self-start">
          {ENDPOINTS.map((e) => (
            <a key={e.id} href={`#${e.id}`} className="state-layer block rounded-m3-sm px-3 py-2 text-m3-body-m">
              {e.title}
            </a>
          ))}
          <a href="#xcconfig" className="state-layer block rounded-m3-sm px-3 py-2 text-m3-body-m font-medium">
            把 Watch 切到此 relay
          </a>
        </aside>
        <div className="space-y-6">
          <Card variant="filled" id="xcconfig" className="p-6">
            <CardTitle>把 Watch 客户端切到此 relay</CardTitle>
            <p className="mt-2 text-m3-body-m text-on-surface-variant">
              打开 <code className="font-mono">Config/Secrets.xcconfig</code>，把下面这段原样贴进去（注意 xcconfig 中
              <code className="font-mono">//</code> 会被当注释，所以 URL 用 <code className="font-mono">/$()/</code>）：
            </p>
            <pre className="mt-3 rounded-m3-sm bg-surface-container-high p-4 font-mono text-m3-body-s">
{`AI_BACKEND_MODE      = relay
AI_RELAY_BASE_URL    = http:/$()/127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = <RELAY_BEARER_TOKEN>
GEMINI_MODEL         = gemini-3-flash-preview`}
            </pre>
          </Card>

          <Tabs
            value={lang}
            onChange={setLang}
            options={[
              { value: "curl", label: "curl" },
              { value: "swift", label: "Swift" },
              { value: "node", label: "Node" },
            ]}
          />
          {ENDPOINTS.map((e) => (
            <Card key={e.id} id={e.id} variant="outlined" className="p-6 scroll-mt-24">
              <CardTitle>{e.title}</CardTitle>
              <p className="mt-1 text-m3-body-m text-on-surface-variant">{e.description}</p>
              <pre className="mt-3 overflow-auto rounded-m3-sm bg-surface-container-high p-4 font-mono text-m3-body-s thin-scroll">{e.request}</pre>
            </Card>
          ))}
        </div>
      </div>
    </AdminShell>
  );
}
