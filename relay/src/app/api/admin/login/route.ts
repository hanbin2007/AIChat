import { config } from "@/lib/config";
import { settingsStore } from "@/lib/store/settings-store";
import { auditLog } from "@/lib/store/audit-log";
import { makeSession, setSessionCookie } from "@/lib/auth/session";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { verifyPassword } from "@/lib/auth/password";

export const runtime = "nodejs";

if (process.env.RELAY_INSECURE_COOKIE === "1" && process.env.NODE_ENV === "production") {
  throw new Error("RELAY_INSECURE_COOKIE=1 is forbidden in production.");
}

export async function POST(req: Request) {
  const body = (await req.json().catch(() => null)) as { username?: string; password?: string } | null;
  if (!body?.username || !body?.password) return errorResponse(400, "Missing credentials.");

  const envMatches =
    config.adminUser &&
    config.adminPassword &&
    body.username === config.adminUser &&
    body.password === config.adminPassword;

  const isSetupDone = await settingsStore().isSetupComplete();
  if (!isSetupDone && envMatches) {
    await settingsStore().seedAdmin(body.username, body.password);
  }

  const user = await settingsStore().authenticateAdmin(body.username, body.password);
  if (user) {
    const session = makeSession(user.username, user.role);
    await setSessionCookie(session);
    await auditLog().append({
      actor: user.username,
      role: user.role,
      action: "admin.login",
      ip: req.headers.get("x-forwarded-for") ?? undefined,
    });
    return jsonResponse(200, { ok: true, role: user.role });
  }

  // Env credentials are accepted ONLY before the operator has seeded a
  // persistent admin. Once setup is complete, env values are break-glass for
  // fresh installs only and should not authenticate live sessions.
  if (!isSetupDone && envMatches) {
    const session = makeSession(body.username, "operator");
    await setSessionCookie(session);
    await auditLog().append({
      actor: body.username,
      role: "operator",
      action: "admin.login.env",
      ip: req.headers.get("x-forwarded-for") ?? undefined,
    });
    return jsonResponse(200, { ok: true, role: "operator" });
  }
  return errorResponse(401, "Invalid credentials.");
}

const ensureCompiled = () => verifyPassword;
void ensureCompiled;
