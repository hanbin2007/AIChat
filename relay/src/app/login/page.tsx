"use client";
import * as React from "react";
import { useRouter } from "next/navigation";
import { Button, Card, CardContent, CardHeader, CardTitle, TextField, Banner, Icon } from "@/components/m3";

export default function LoginPage() {
  const router = useRouter();
  const [username, setUsername] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const [loading, setLoading] = React.useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const res = await fetch("/api/admin/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    setLoading(false);
    if (!res.ok) {
      const data = (await res.json().catch(() => ({}))) as { message?: string };
      setError(data.message ?? "登录失败");
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface-container-low p-6">
      <Card variant="elevated" className="w-full max-w-md">
        <CardHeader>
          <div className="flex items-center gap-3">
            <span className="flex h-12 w-12 items-center justify-center rounded-m3-md bg-primary-container text-on-primary-container">
              <Icon name="hub" size={28} />
            </span>
            <div>
              <CardTitle>AIChat Relay</CardTitle>
              <div className="text-m3-body-s text-on-surface-variant">管理控制台</div>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="flex flex-col gap-4">
            <TextField
              label="用户名"
              leading="person"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              autoFocus
            />
            <TextField
              label="密码"
              type="password"
              leading="lock"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
            />
            {error && <Banner tone="error">{error}</Banner>}
            <Button type="submit" loading={loading} className="w-full">登录</Button>
            <p className="text-center text-m3-body-s text-on-surface-variant">
              首次部署？<a href="/setup" className="text-primary hover:underline">前往初始化</a>
            </p>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
