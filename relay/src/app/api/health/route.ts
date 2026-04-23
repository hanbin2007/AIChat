import { config, configDiagnostics } from "@/lib/config";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET() {
  return jsonResponse(200, {
    ok: true,
    version: process.env.npm_package_version ?? "1.0.0",
    billingMode: config.billingMode,
    diagnostics: configDiagnostics(),
  });
}
