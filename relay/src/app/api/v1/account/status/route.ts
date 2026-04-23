import { authenticate } from "@/lib/auth/bearer";
import { billingStore } from "@/lib/store/billing-store";
import { errorResponse, jsonResponse } from "@/lib/api/error";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const auth = await authenticate(req);
  const deviceID = req.headers.get("x-aichat-device-id") ?? undefined;

  if (auth?.kind === "client" && auth.clientKey) {
    const status = await billingStore().getAccountStatus(auth.clientKey);
    if (!status) return errorResponse(404, "Account not found.");
    return jsonResponse(200, status);
  }

  if (deviceID) {
    const device = await billingStore().findDevice(deviceID);
    if (!device) return errorResponse(404, "Device not bound.");
    const snapshot = await billingStore().snapshot();
    const account = snapshot.accounts[device.accountID];
    const key = Object.values(snapshot.keys).find(
      (k) => k.deviceID === deviceID && k.state === "active",
    );
    if (!account || !key) return errorResponse(404, "Account not found.");
    const status = await billingStore().getAccountStatus(key);
    if (!status) return errorResponse(404, "Account not found.");
    return jsonResponse(200, status);
  }

  return errorResponse(401, "Unauthorized relay request.");
}
