import { settingsStore } from "@/lib/store/settings-store";
import { makeSession, setSessionCookie } from "@/lib/auth/session";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { auditLog } from "@/lib/store/audit-log";

export const runtime = "nodejs";

export async function GET() {
  const done = await settingsStore().isSetupComplete();
  return jsonResponse(200, { setupComplete: done });
}

export async function POST(req: Request) {
  const body = (await req.json().catch(() => null)) as { username?: string; password?: string } | null;
  if (!body?.username || !body?.password || body.password.length < 8) {
    return errorResponse(400, "Username and password (≥8 chars) required.");
  }
  if (await settingsStore().isSetupComplete()) {
    return errorResponse(409, "Setup already complete.");
  }
  const user = await settingsStore().seedAdmin(body.username, body.password);
  await setSessionCookie(makeSession(user.username, "operator"));
  await auditLog().append({
    actor: user.username,
    role: "operator",
    action: "admin.setup",
  });
  return jsonResponse(200, { ok: true });
}
