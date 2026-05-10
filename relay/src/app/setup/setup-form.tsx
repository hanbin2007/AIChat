"use client";
import * as React from "react";
import { useRouter } from "next/navigation";
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import CardHeader from "@mui/material/CardHeader";
import Stack from "@mui/material/Stack";
import Stepper from "@mui/material/Stepper";
import Step from "@mui/material/Step";
import StepLabel from "@mui/material/StepLabel";
import TextField from "@mui/material/TextField";
import Button from "@mui/material/Button";
import Alert from "@mui/material/Alert";
import AlertTitle from "@mui/material/AlertTitle";
import Typography from "@mui/material/Typography";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import CheckIcon from "@mui/icons-material/Check";

const STEPS = ["欢迎", "管理员账户", "上游 Gemini", "Bearer Token", "完成"] as const;

export default function SetupForm() {
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
    <Box
      sx={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        bgcolor: "background.default",
        p: 3,
      }}
    >
      <Card sx={{ width: "100%", maxWidth: 720, boxShadow: 4 }}>
        <CardHeader
          title="AIChat Relay · 首次部署"
          titleTypographyProps={{ variant: "h6" }}
        />
        <Box sx={{ px: 3, pb: 1 }}>
          <Stepper activeStep={step} alternativeLabel>
            {STEPS.map((label) => (
              <Step key={label}>
                <StepLabel>{label}</StepLabel>
              </Step>
            ))}
          </Stepper>
        </Box>
        <CardContent>
          {step === 0 && (
            <Stack spacing={2}>
              <Typography variant="body1">
                欢迎使用 AIChat Relay。这是一台企业级中继网关，替 AIChat 客户端持有 Gemini API key、进行鉴权与额度管理。
              </Typography>
              <Typography variant="body2" sx={{ color: "text.secondary" }}>
                接下来会花不到 1 分钟创建管理员账户、确认 Gemini 配置，并展示 Watch 客户端的接入片段。
              </Typography>
              <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                <Button onClick={() => setStep(1)} endIcon={<ArrowForwardIcon />}>
                  开始
                </Button>
              </Box>
            </Stack>
          )}
          {step === 1 && (
            <Stack spacing={2}>
              <TextField
                label="管理员用户名"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
              />
              <TextField
                label="管理员密码"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                helperText="至少 8 位；登录后可从 Settings 修改"
              />
              {error && <Alert severity="error">{error}</Alert>}
              <Box sx={{ display: "flex", justifyContent: "flex-end", gap: 1 }}>
                <Button variant="text" onClick={() => setStep(0)}>
                  上一步
                </Button>
                <Button
                  disabled={!username || password.length < 8}
                  onClick={() => setStep(2)}
                  endIcon={<ArrowForwardIcon />}
                >
                  下一步
                </Button>
              </Box>
            </Stack>
          )}
          {step === 2 && (
            <Stack spacing={2}>
              <Alert severity="info">
                <AlertTitle>Gemini API key</AlertTitle>
                API key 需要通过环境变量{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  GEMINI_API_KEY
                </Typography>{" "}
                提供，或启动前写入{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  .env
                </Typography>
                。登录后可在 Settings 检查状态。
              </Alert>
              <Box sx={{ display: "flex", justifyContent: "space-between" }}>
                <Button variant="text" onClick={() => setStep(1)}>
                  上一步
                </Button>
                <Button onClick={() => setStep(3)} endIcon={<ArrowForwardIcon />}>
                  下一步
                </Button>
              </Box>
            </Stack>
          )}
          {step === 3 && (
            <Stack spacing={2}>
              <Alert severity="info">
                <AlertTitle>Bearer Token</AlertTitle>
                启动时通过{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  RELAY_BEARER_TOKEN
                </Typography>{" "}
                提供主 bearer。 登录后可在 Settings → Auth &amp; Tokens 签发额外 token（支持分 scope、限流、吊销）。
              </Alert>
              {error && <Alert severity="error">{error}</Alert>}
              <Box sx={{ display: "flex", justifyContent: "space-between" }}>
                <Button variant="text" onClick={() => setStep(2)}>
                  上一步
                </Button>
                <Button onClick={completeSetup} disabled={busy} endIcon={<CheckIcon />}>
                  {busy ? "处理中…" : "创建并登录"}
                </Button>
              </Box>
            </Stack>
          )}
          {step === 4 && (
            <Stack spacing={2}>
              <Alert severity="success">
                <AlertTitle>部署完成</AlertTitle>
                管理员账户已建立。现在可以把 Watch 的{" "}
                <Typography component="code" sx={{ fontFamily: "monospace" }}>
                  AI_RELAY_BASE_URL
                </Typography>{" "}
                指向本 relay。
              </Alert>
              <Box
                sx={{
                  bgcolor: "action.hover",
                  borderRadius: 2,
                  p: 2,
                  fontFamily: "monospace",
                  fontSize: "0.875rem",
                  whiteSpace: "pre-line",
                }}
              >
                {`AI_BACKEND_MODE = relay
AI_RELAY_BASE_URL = http://127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = <RELAY_BEARER_TOKEN>
GEMINI_MODEL = gemini-3-flash-preview`}
              </Box>
              <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                <Button
                  onClick={() => router.push("/dashboard")}
                  endIcon={<ArrowForwardIcon />}
                >
                  进入 Dashboard
                </Button>
              </Box>
            </Stack>
          )}
        </CardContent>
      </Card>
    </Box>
  );
}
