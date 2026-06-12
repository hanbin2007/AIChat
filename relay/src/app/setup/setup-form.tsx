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
AI_RELAY_BASE_URL = http:/$()/<your-relay-host>:8787`;

function setupErrorMessage(status?: number) {
  if (status === 409) {
    return "初始化已完成。请前往登录页，或直接进入控制台。";
  }
  if (status === 400) {
    return "用户名和至少 8 位的新密码不能为空。";
  }
  return "初始化失败，请稍后重试。";
}

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
        setError(setupErrorMessage(res.status));
        return;
      }
      router.replace("/dashboard");
    } catch {
      setError("网络错误，请检查连接后重试。");
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
                autoComplete="username"
                autoFocus
                fullWidth
              />
              <TextField
                label="密码（至少 8 位）"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="new-password"
                helperText="至少 8 位，建议使用独立强密码。"
                fullWidth
              />
              <TextField
                label="确认密码"
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                autoComplete="new-password"
                error={confirm.length > 0 && password !== confirm}
                helperText={
                  confirm.length > 0 && password !== confirm
                    ? "两次输入不一致"
                    : "请再次输入新密码。"
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
                ；客户端将携带此值访问 /api/v1。点击「创建管理员并进入控制台」会创建管理员账户并进入控制台。
              </Alert>
              {error ? (
                <Alert severity="error">
                  <Stack spacing={1.5}>
                    <Typography variant="body2">{error}</Typography>
                    <Stack direction="row" spacing={1} sx={{ flexWrap: "wrap" }}>
                      <Button
                        variant="outlined"
                        size="small"
                        onClick={() => router.replace("/login")}
                      >
                        前往登录
                      </Button>
                      <Button
                        variant="outlined"
                        size="small"
                        onClick={() => router.replace("/dashboard")}
                      >
                        进入控制台
                      </Button>
                    </Stack>
                  </Stack>
                </Alert>
              ) : null}
              <Stack direction="row" spacing={1.5} justifyContent="flex-end">
                <Button onClick={back} disabled={loading}>
                  上一步
                </Button>
                <Button variant="contained" onClick={submit} disabled={loading}>
                  {loading ? "处理中…" : "创建管理员并进入控制台"}
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
                  router.replace("/dashboard");
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
