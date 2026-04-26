import { readSession } from "@/lib/auth/session";
import { jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET() {
  const session = await readSession();
  return jsonResponse(200, { session });
}
