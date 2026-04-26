import { billingStore } from "@/lib/store/billing-store";
import { pick } from "@/lib/gemini/dual-key";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import type { DevicePlatform } from "@/lib/billing/types";

export const runtime = "nodejs";

const VALID_PLATFORMS: DevicePlatform[] = ["iPhone", "watch", "mac", "unknown"];

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/activation/bootstrap");
  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Invalid JSON body" });
    return errorResponse(400, "Invalid JSON body.");
  }

  const deviceID = pick<string>(body, "deviceID", "device_id");
  const rawPlatform = pick<string>(body, "platform") ?? "unknown";
  const alias = pick<string>(body, "deviceAlias", "device_alias");
  if (!deviceID) {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Missing deviceID" });
    return errorResponse(400, "Missing deviceID.");
  }
  const platform: DevicePlatform = VALID_PLATFORMS.includes(rawPlatform as DevicePlatform)
    ? (rawPlatform as DevicePlatform)
    : "unknown";

  try {
    const result = await billingStore().bootstrapTrial({ deviceID, platform, alias });
    const status = await billingStore().getAccountStatus(result.key);
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "trial bootstrap" });
    return jsonResponse(200, status);
  } catch (err) {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: (err as Error).message });
    return errorResponse(400, (err as Error).message);
  }
}
