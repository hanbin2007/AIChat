"use client";
import * as React from "react";
import { useRouter } from "next/navigation";
import { Button, Card, CardContent, CardHeader, CardTitle, TextField, Banner, Icon } from "@/components/m3";

const STEPS = ["欢迎", "管理员账户", "上游 Gemini", "Bearer Token", "完成"] as const;

export default function SetupPage() {
  const router = useRouter();
  const [step, setStep] = React.useState(0);
  const [username, setUsername] = React.useState("admin");
  const [password, setPassword] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState(false);

  async function completeSetup() {
    setError(null);
    setBusy(true);
    const res = await fetch("/api/admin/setup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    setBusy(false);
    if (!res.ok) {
      const data = (await res.json().catch(() => ({}))) as { message?: string };
      setError(data.message ?? "初始化失败");
      return;
    }
    setStep(4);
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface-container-low p-6">
      <Card variant="elevated" className="w-full max-w-2xl">
        <CardHeader>
          <CardTitle>AIChat Relay · 首次部署</CardTitle>
          <div className="mt-4 flex items-center gap-2">
            {STEPS.map((label, i) => (
              <React.Fragment key={label}>
                <div
                  className={`flex h-8 w-8 items-center justify-center rounded-full text-m3-label-m ${
                    i === step
                      ? "bg-primary text-on-primary"
                      : i < step
                        ? "bg-secondary-container text-on-secondary-container"
                        : "bg-surface-container-high text-on-surface-variant"
                  }`}
                >
                  {i < step ? <Icon name="check" size={16} /> : i + 1}
                </div>
                {i < STEPS.length - 1 && (
                  <div className={`h-px flex-1 ${i < step ? "bg-primary" : "bg-outline-variant"}`} />
                )}
              </React.Fragment>
            ))}
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {step === 0 && (
            <div>
              <p className="text-m3-body-l text-on-surface">
                欢迎使用 AIChat Relay。这是一台企业级中继网关，替 AIChat 客户端持有 Gemini API key、进行鉴权与额度管理。
              </p>
              <p className="mt-2 text-m3-body-m text-on-surface-variant">
                接下来会花不到 1 分钟创建管理员账户、确认 Gemini 配置，并展示 Watch 客户端的接入片段。
              </p>
              <div className="mt-6 flex justify-end">
                <Button onClick={() => setStep(1)} trailing="arrow_forward">开始</Button>
              </div>
            </div>
          )}
          {step === 1 && (
            <div className="space-y-4">
              <TextField label="管理员用户名" value={username} onChange={(e) => setUsername(e.target.value)} />
              <TextField
                label="管理员密码"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                supporting="至少 8 位；登录后可从 Settings 修改"
              />
              {error && <Banner tone="error">{error}</Banner>}
              <div className="flex justify-end gap-2">
                <Button variant="text" onClick={() => setStep(0)}>上一步</Button>
                <Button
                  disabled={!username || password.length < 8}
                  onClick={() => setStep(2)}
                  trailing="arrow_forward"
                >
                  下一步
                </Button>
              </div>
            </div>
          )}
          {step === 2 && (
            <div className="space-y-4">
              <Banner tone="info" title="Gemini API key">
                API key 需要通过环境变量 <code className="font-mono text-m3-label-l">GEMINI_API_KEY</code> 提供，
                或启动前写入 <code className="font-mono text-m3-label-l">.env</code>。登录后可在 Settings 检查状态。
              </Banner>
              <div className="flex justify-between">
                <Button variant="text" onClick={() => setStep(1)}>上一步</Button>
                <Button onClick={() => setStep(3)} trailing="arrow_forward">下一步</Button>
              </div>
            </div>
          )}
          {step === 3 && (
            <div className="space-y-4">
              <Banner tone="info" title="Bearer Token">
                启动时通过 <code className="font-mono text-m3-label-l">RELAY_BEARER_TOKEN</code> 提供主 bearer。
                登录后可在 Settings → Auth & Tokens 签发额外 token（支持分 scope、限流、吊销）。
              </Banner>
              <div className="flex justify-between">
                <Button variant="text" onClick={() => setStep(2)}>上一步</Button>
                <Button onClick={completeSetup} loading={busy} trailing="check">
                  创建并登录
                </Button>
              </div>
            </div>
          )}
          {step === 4 && (
            <div className="space-y-4">
              <Banner tone="success" title="部署完成">
                管理员账户已建立。现在可以把 Watch 的 <code className="font-mono text-m3-label-l">AI_RELAY_BASE_URL</code> 指向本 relay。
              </Banner>
              <div className="rounded-m3-md bg-surface-container p-4 font-mono text-m3-body-s">
                AI_BACKEND_MODE = relay<br />
                AI_RELAY_BASE_URL = http:/$()/127.0.0.1:8787<br />
                AI_RELAY_BEARER_TOKEN = &lt;RELAY_BEARER_TOKEN&gt;<br />
                GEMINI_MODEL = gemini-3-flash-preview
              </div>
              <div className="flex justify-end">
                <Button onClick={() => router.push("/dashboard")} trailing="arrow_forward">
                  进入 Dashboard
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
