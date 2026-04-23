import { clearSessionCookie } from "@/lib/auth/session";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function POST() {
  await clearSessionCookie();
  return jsonResponse(200, { ok: true });
}
