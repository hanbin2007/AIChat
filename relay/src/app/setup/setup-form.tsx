"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import { Stack } from "@/components/lib/stack";
import Stepper from "@mui/material/Stepper";
import Step from "@mui/material/Step";
import StepLabel from "@mui/material/StepLabel";
import Button from "@mui/material/Button";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import Alert from "@mui/material/Alert";
import AlertTitle from "@mui/material/AlertTitle";

const STEPS = ["欢迎", "管理员账户", "上游 Gemini", "Bearer Token", "完成"];

const XCCONFIG_SNIPPET = `// AIChat 客户端 — 在 Config/Secrets.xcconfig 中设置
AI_BACKEND_MODE = relay
RELAY_BASE_URL = http:/$()/<your-relay-host>:8787
RELAY_BEARER_TOKEN = <您在 .env 中配置的 RELAY_BEARER_TOKEN>`;

export default function SetupForm() {
  const router = useRouter();
  const [active, setActive] = useState(0);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const passwordValid = password.length >= 8 && password === confirm;

  function next() {
    setError(null);
    setActive((s) => Math.min(s + 1, STEPS.length - 1));
  }

  function back() {
    setError(null);
    setActive((s) => Math.max(s - 1, 0));
  }

  async function submit() {
    setError(null);
    setLoading(true);
    try {
      const res = await fetch("/api/admin/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      if (!res.ok) {
        const data = (await res.json().catch(() => ({}))) as { message?: string };
        setError(data.message ?? "初始化失败");
        return;
      }
      const login = await fetch("/api/admin/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      if (!login.ok) {
        setError("初始化成功，但自动登录失败，请手动登录");
        return;
      }
      next();
    } catch {
      setError("网络错误，请重试");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Box
      sx={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        p: 3,
      }}
    >
      <Card sx={{ width: "100%", maxWidth: 720 }}>
        <CardContent sx={{ p: { xs: 3, sm: 4 } }}>
          <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
            AIChat Relay 初始化
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            五步搞定首次部署
          </Typography>

          <Stepper activeStep={active} alternativeLabel sx={{ mb: 4 }}>
            {STEPS.map((label) => (
              <Step key={label}>
                <StepLabel>{label}</StepLabel>
              </Step>
            ))}
          </Stepper>

          {active === 0 ? (
            <Stack spacing={2}>
              <Typography>欢迎使用 AIChat Relay。本向导将协助您完成：</Typography>
              <Box component="ul" sx={{ pl: 3, color: "text.secondary", m: 0 }}>
                <li>创建管理员账户</li>
                <li>确认上游 Gemini API Key 已就绪</li>
                <li>确认客户端使用的 Bearer Token</li>
              </Box>
              <Button variant="contained" size="large" onClick={next}>
                开始
              </Button>
            </Stack>
          ) : null}

          {active === 1 ? (
            <Stack spacing={2}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                管理员账户
              </Typography>
              <TextField
                label="用户名"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                autoFocus
                fullWidth
              />
              <TextField
                label="密码（至少 8 位）"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                fullWidth
              />
              <TextField
                label="确认密码"
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                error={confirm.length > 0 && password !== confirm}
                helperText={
                  confirm.length > 0 && password !== confirm ? "两次输入不一致" : undefined
                }
                fullWidth
              />
              <Stack direction="row" spacing={1.5} justifyContent="flex-end">
                <Button onClick={back}>上一步</Button>
                <Button
                  variant="contained"
                  onClick={next}
                  disabled={!username || !passwordValid}
                >
                  下一步
                </Button>
              </Stack>
            </Stack>
          ) : null}

          {active === 2 ? (
            <Stack spacing={2}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                上游 Gemini API Key
              </Typography>
              <Alert severity="info">
                <AlertTitle>请在部署环境的 .env 中设置</AlertTitle>
                <Typography
                  variant="body2"
                  component="code"
                  sx={{ fontFamily: "var(--font-mono)", display: "block", mt: 1 }}
                >
                  GEMINI_API_KEY=your_gemini_api_key
                </Typography>
              </Alert>
              <Stack direction="row" spacing={1.5} justifyContent="flex-end">
                <Button onClick={back}>上一步</Button>
                <Button variant="contained" onClick={next}>
                  下一步
                </Button>
              </Stack>
            </Stack>
          ) : null}

          {active === 3 ? (
            <Stack spacing={2}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                Bearer Token
              </Typography>
              <Alert severity="info">
                <AlertTitle>客户端 Bearer Token</AlertTitle>
                请在部署环境的 .env 中设置{" "}
                <Box component="code" sx={{ fontFamily: "var(--font-mono)" }}>
                  RELAY_BEARER_TOKEN
                </Box>
                ；客户端将携带此值访问 /api/v1。点击「创建并登录」会创建管理员账户并自动登录。
              </Alert>
              {error ? <Alert severity="error">{error}</Alert> : null}
              <Stack direction="row" spacing={1.5} justifyContent="flex-end">
                <Button onClick={back} disabled={loading}>
                  上一步
                </Button>
                <Button variant="contained" onClick={submit} disabled={loading}>
                  {loading ? "处理中…" : "创建并登录"}
                </Button>
              </Stack>
            </Stack>
          ) : null}

          {active === 4 ? (
            <Stack spacing={2}>
              <Alert severity="success">
                <AlertTitle>初始化完成</AlertTitle>
                Relay 已就绪。下一步：把以下片段加入 AIChat 客户端的{" "}
                <Box component="code" sx={{ fontFamily: "var(--font-mono)" }}>
                  Config/Secrets.xcconfig
                </Box>
                。
              </Alert>
              <Box
                component="pre"
                sx={{
                  fontFamily: "var(--font-mono)",
                  fontSize: "0.8125rem",
                  bgcolor: "action.hover",
                  p: 2,
                  borderRadius: 1,
                  m: 0,
                  overflowX: "auto",
                }}
              >
                {XCCONFIG_SNIPPET}
              </Box>
              <Button
                variant="contained"
                size="large"
                onClick={() => {
                  router.push("/dashboard");
                  router.refresh();
                }}
              >
                进入控制台
              </Button>
            </Stack>
          ) : null}
        </CardContent>
      </Card>
    </Box>
  );
}
