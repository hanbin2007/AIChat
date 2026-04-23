import { requireAdmin } from "@/lib/auth/admin-guard";
import { requestLog, type ActivityEntry } from "@/lib/store/request-log";

export const runtime = "nodejs";

export async function GET() {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;

  const encoder = new TextEncoder();
  const log = requestLog();
  let listener: ((entry: ActivityEntry) => void) | null = null;

  const stream = new ReadableStream({
    start(controller) {
      const send = (event: string, data: unknown) => {
        controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
      };
      send("ping", { ok: true });
      listener = (entry) => send("activity", entry);
      log.on("activity", listener);
    },
    cancel() {
      if (listener) log.off("activity", listener);
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
