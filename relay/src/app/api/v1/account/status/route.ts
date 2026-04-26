import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { beginObserve, finishObserve } from "@/lib/api/observe";
import { errorResponse, jsonResponse } from "@/lib/api/error";
import { projectAccountStatus } from "@/app/api/v1/_schemas/projections";
import { adoptRequestId } from "@/app/api/v1/_schemas/request-id";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const ctx = beginObserve(req, "/api/v1/account/status");
  adoptRequestId(req, ctx);
  const auth = await authenticate(req);
  if (!auth) {
    await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
    return errorResponse(401, "Unauthorized relay request.");
  }
  ctx.auth = auth;

  if (auth.kind === "client" && auth.clientKey) {
    const status = await billingStore().getAccountStatus(auth.clientKey);
    if (!status) {
      await finishObserve(ctx, { statusCode: 404, level: "warning", category: "failure", message: "account not found" });
      return errorResponse(404, "Account not found.");
    }
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "completed", message: "status (client)" });
    return jsonResponse(200, projectAccountStatus(status));
  }

  if (auth.kind === "admin") {
    const deviceID = req.headers.get("x-aichat-device-id") ?? undefined;
    if (!deviceID) {
      await finishObserve(ctx, {
        statusCode: 400,
        level: "warning",
        category: "failure",
        message: "x-aichat-device-id required for admin status",
      });
      return errorResponse(400, "Missing x-aichat-device-id header.");
    }
    const device = await billingStore().findDevice(deviceID);
    if (!device) {
      await finishObserve(ctx, { statusCode: 404, level: "warning", category: "failure", message: "device not bound" });
      return errorResponse(404, "Device not bound.");
    }
    const snapshot = await billingStore().snapshot();
    const account = snapshot.accounts[device.accountID];
    const key = Object.values(snapshot.keys).find((k) => k.deviceID === deviceID && k.state === "active");
    if (!account || !key) {
      await finishObserve(ctx, { statusCode: 404, level: "warning", category: "failure", message: "account not found" });
      return errorResponse(404, "Account not found.");
    }
    const status = await billingStore().getAccountStatus(key);
    if (!status) {
      await finishObserve(ctx, { statusCode: 404, level: "warning", category: "failure", message: "account not found" });
      return errorResponse(404, "Account not found.");
    }
    await finishObserve(ctx, { statusCode: 200, level: "success", category: "completed", message: "status (admin)" });
    return jsonResponse(200, projectAccountStatus(status));
  }

  await finishObserve(ctx, { statusCode: 401, level: "warning", category: "failure", message: "Unauthorized" });
  return errorResponse(401, "Unauthorized relay request.");
}
