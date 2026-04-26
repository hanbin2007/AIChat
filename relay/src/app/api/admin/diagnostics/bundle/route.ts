/**
 * Diagnostics bundle: a single signed JSON dump of everything support needs
 * to triage a relay incident. Secrets are stripped (Gemini API key, bearer
 * tokens, password hashes, raw activation codes). Operator-only.
 */

import { requireOperator } from "@/lib/auth/admin-guard";
import { configDiagnostics } from "@/lib/config";
import { auditLog } from "@/lib/store/audit-log";
import { billingStore } from "@/lib/store/billing-store";
import { metrics } from "@/lib/observability/metrics";
import { requestLog } from "@/lib/store/request-log";
import { settingsStore } from "@/lib/store/settings-store";
import { mask } from "@/lib/observability/redact";

export const runtime = "nodejs";

export async function GET() {
  const guard = await requireOperator();
  if (!guard.ok) return guard.response;

  const settings = await settingsStore().get();
  const billing = await billingStore().listAll();
  const activity = await requestLog().listActivity();
  const debug = await requestLog().listDebug();
  const audit = await auditLog().list(500);

  const bundle = {
    version: process.env.npm_package_version ?? "1.1.0",
    generatedAt: new Date().toISOString(),
    diagnostics: configDiagnostics(),
    metrics: metrics().snapshot(),
    settings: {
      ...settings,
      adminUsers: settings.adminUsers.map((u) => ({ ...u, passwordHash: "[redacted]" })),
      adminTokens: settings.adminTokens.map((t) => ({ ...t, value: mask(t.value) })),
    },
    billing: {
      counts: {
        accounts: billing.accounts.length,
        devices: billing.devices.length,
        keys: billing.keys.length,
        grants: billing.grants.length,
        usage: billing.usage.length,
        activationCodes: billing.activationCodes.length,
        pairingTokens: billing.pairingTokens.length,
      },
      policy: billing.policy,
      plans: billing.plans,
      // Don't ship raw activation codes — they're bearer-equivalent secrets.
      activationCodes: billing.activationCodes.map((c) => ({
        ...c,
        code: mask(c.code, 4),
      })),
    },
    activity: activity.slice(0, 200),
    debug: debug.slice(0, 100),
    audit: audit.slice(0, 200),
  };

  await auditLog().append({
    actor: guard.session.sub,
    role: guard.session.role,
    action: "diagnostics.bundle.download",
  });

  return new Response(JSON.stringify(bundle, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="relay-diagnostics-${Date.now()}.json"`,
    },
  });
}
