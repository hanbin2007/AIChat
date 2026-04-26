/**
 * Adopt the middleware-minted `x-relay-request-id` as the activity row id so
 * client correlation IDs flow through to the activity log without forcing
 * `beginObserve` to mint a second one.
 *
 * TODO(A2): fold into `beginObserve` when the observability helper grows an
 * override parameter.
 */

import type { ObserveContext } from "@/lib/api/observe";

export function adoptRequestId(req: Request, ctx: ObserveContext): void {
  const incoming = req.headers.get("x-relay-request-id");
  if (incoming) ctx.requestID = incoming;
}
