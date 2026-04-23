import { readSession } from "@/lib/auth/session";
import { errorResponse } from "@/lib/api/error";

export async function requireAdmin() {
  const session = await readSession();
  if (!session) return { ok: false as const, response: errorResponse(401, "Admin session required.") };
  return { ok: true as const, session };
}
