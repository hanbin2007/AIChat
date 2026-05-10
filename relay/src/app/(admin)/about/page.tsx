import { AdminShell } from "@/components/admin-shell";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/m3";
import { config, configDiagnostics } from "@/lib/config";

export const dynamic = "force-dynamic";

export default function AboutPage() {
  const diag = configDiagnostics();
  return (
    <AdminShell title="About" breadcrumb={["System"]}>
      <div className="mx-auto max-w-3xl space-y-4 p-6">
        <Card variant="elevated" className="p-6">
          <CardTitle>AIChat Relay</CardTitle>
          <p className="mt-2 text-m3-body-m text-on-surface-variant">
            企业级 Next.js 中继网关。与 macOS AIChat Relay 在路径、SSE 事件名、Gemini 请求变换上完全兼容；
            在此之上提供 Material Design 3 管理控制台、计费状态机、可视化策略编辑器，以及会话级对话重建。
          </p>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>部署信息</CardTitle>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-1 gap-3 md:grid-cols-2 text-m3-body-m">
              <Info label="版本" value="1.0.0" />
              <Info label="Node" value={process.version} />
              <Info label="监听端口" value={String(config.port)} />
              <Info label="数据目录" value={config.dataDir} />
              <Info label="Billing 模式" value={diag.billingMode} />
              <Info label="Gemini key" value={diag.geminiConfigured ? "已配置" : "未配置"} />
              <Info label="Bearer token" value={diag.bearerConfigured ? "已配置" : "未配置"} />
              <Info label="Session secret" value={diag.sessionSecretConfigured ? "已配置" : "未配置"} />
            </dl>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>诊断与支持</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-3">
            <a
              href="/api/admin/requests"
              className="inline-flex items-center gap-2 rounded-m3-md border border-outline px-4 py-2 text-m3-label-l text-primary hover:border-primary"
            >
              下载 requests JSON
            </a>
            <a
              href="/api/admin/audit"
              className="inline-flex items-center gap-2 rounded-m3-md border border-outline px-4 py-2 text-m3-label-l text-primary hover:border-primary"
            >
              下载 audit JSON
            </a>
            <a
              href="/api/health"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 rounded-m3-md border border-outline px-4 py-2 text-m3-label-l text-primary hover:border-primary"
            >
              /api/health
            </a>
          </CardContent>
        </Card>
      </div>
    </AdminShell>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-m3-label-m text-on-surface-variant">{label}</dt>
      <dd className="mt-1 font-mono">{value}</dd>
    </div>
  );
}
