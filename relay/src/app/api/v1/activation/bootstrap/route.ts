import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { bootstrapRequestSchema, formatZodIssues } from "@/app/api/v1/_schemas";
import { redactBillingBody } from "@/app/api/v1/_schemas/redact";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

const BOOTSTRAP_WINDOW_MS = 24 * 60 * 60 * 1000;
const BOOTSTRAP_MAX_PER_WINDOW = 1;

interface BootstrapBucket {
  count: number;
  windowStart: number;
}

declare global {
  // eslint-disable-next-line no-var
  var __bootstrapAttempts: Map<string, BootstrapBucket> | undefined;
}

// TODO(A2): migrate to BillingStore so the rate-limit survives restarts and
// is consistent across replicas. For now this is a defense-in-depth in-memory
// guard backed by a `globalThis` singleton (matches the other relay stores).
function bootstrapRateMap(): Map<string, BootstrapBucket> {
  if (!globalThis.__bootstrapAttempts) globalThis.__bootstrapAttempts = new Map();
  return globalThis.__bootstrapAttempts;
}

function bootstrapRateCheck(ip: string): { allowed: boolean; retryAfterSec: number } {
  if (process.env.RELAY_BOOTSTRAP_RATELIMIT_DISABLED === "1") {
    return { allowed: true, retryAfterSec: 0 };
  }
  const map = bootstrapRateMap();
  const now = Date.now();
  const entry = map.get(ip);
  if (!entry || now - entry.windowStart >= BOOTSTRAP_WINDOW_MS) {
    map.set(ip, { count: 1, windowStart: now });
    return { allowed: true, retryAfterSec: 0 };
  }
  if (entry.count < BOOTSTRAP_MAX_PER_WINDOW) {
    entry.count += 1;
    return { allowed: true, retryAfterSec: 0 };
  }
  return {
    allowed: false,
    retryAfterSec: Math.ceil((entry.windowStart + BOOTSTRAP_WINDOW_MS - now) / 1000),
  };
}

function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    req.headers.get("x-real-ip") ||
    "unknown"
  );
}

export async function POST(req: Request) {
  const ctx = beginObserve(req, "/api/v1/activation/bootstrap");
  adoptRequestId(req, ctx);

  // Path (a): an existing client bearer renewing. Path (b): per-IP 1/24h.
  const auth = await authenticate(req);
  const isClientRenewal = auth?.kind === "client" && !!auth.clientKey;
  if (auth) ctx.auth = auth;
  if (!isClientRenewal) {
    const ip = clientIp(req);
    const limit = bootstrapRateCheck(ip);
    if (!limit.allowed) {
      await finishObserve(ctx, {
        statusCode: 429,
        level: "warning",
        category: "billing",
        message: `bootstrap rate limit (${limit.retryAfterSec}s)`,
      });
      return new Response(
        JSON.stringify({ message: "Trial bootstrap rate limit reached. Try again later." }),
        {
          status: 429,
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Retry-After": String(limit.retryAfterSec),
          },
        },
      );
    }
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: "Invalid JSON body" });
    return errorResponse(400, "Invalid JSON body.");
  }
  const parsed = bootstrapRequestSchema.safeParse(rawBody);
  if (!parsed.success) {
    ctx.requestBody = redactBillingBody(rawBody);
    const message = formatZodIssues(parsed.error);
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message });
    return errorResponse(400, message);
  }
  const body = parsed.data;
  ctx.requestBody = redactBillingBody(rawBody);

  try {
    const result = await billingStore().bootstrapTrial({
      deviceID: body.deviceID,
      platform: body.platform,
      alias: body.deviceAlias,
    });
    const status = await billingStore().getAccountStatus(result.key);
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "billing", message: "trial bootstrap" });
    return jsonResponse(200, status);
  } catch (err) {
    await finishObserve(ctx, { statusCode: 400, level: "error", category: "failure", message: (err as Error).message });
    return errorResponse(400, (err as Error).message);
  }
}
