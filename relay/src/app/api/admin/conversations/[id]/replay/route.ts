/**
 * Synthesized SSE replay. We don't store individual delta frames (only the
 * merged answer / thought), so we re-chunk the merged text in 60-character
 * pieces and stream them with a small inter-chunk delay scaled by the
 * `speed` query param (1, 2, 4, 8). Between turns we honour the original
 * elapsed time (compressed by the same speed factor).
 *
 * Event names match the live /api/v1/chat/stream protocol so the same UI
 * code can render both live + replayed conversations.
 */

import { requireAdmin } from "@/lib/auth/admin-guard";
import { getConversation } from "@/lib/store/conversations";
import { errorResponse } from "@/lib/api/error";

export const runtime = "nodejs";
export const maxDuration = 600;

const CHUNK_SIZE = 60;
const BETWEEN_CHUNK_MS = 30;
const MAX_GAP_MS = 5_000;

function chunkString(text: string, size: number): string[] {
  if (!text) return [];
  const out: string[] = [];
  for (let i = 0; i < text.length; i += size) out.push(text.slice(i, i + size));
  return out;
}

export async function GET(req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  const conversation = await getConversation(id);
  if (!conversation) return errorResponse(404, "Conversation not found.");

  const url = new URL(req.url);
  const speed = Math.max(1, Math.min(16, Number(url.searchParams.get("speed") ?? 1)));

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const send = (event: string, data: Record<string, unknown>) => {
        controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
      };
      const sleep = (ms: number) =>
        new Promise<void>((resolve) => setTimeout(resolve, ms));
      const aborted = { value: false };
      req.signal.addEventListener("abort", () => {
        aborted.value = true;
      });

      send("conversation_start", {
        type: "conversation_start",
        id: conversation.id,
        title: conversation.title,
        turnCount: conversation.turnCount,
        speed,
      });

      let previousTimestamp: number | null = null;
      for (const turn of conversation.turns) {
        if (aborted.value) break;
        // Pause the original inter-turn gap (capped + scaled).
        const turnStartMs = new Date(turn.timestamp).getTime();
        if (previousTimestamp !== null) {
          const gap = Math.min(MAX_GAP_MS, turnStartMs - previousTimestamp);
          if (gap > 0) await sleep(gap / speed);
        }
        previousTimestamp = turnStartMs;

        send("turn_start", {
          type: "turn_start",
          turnId: turn.id,
          modelID: turn.modelID,
          userText: turn.userText,
          credits: turn.credits,
        });

        if (turn.thoughtText) {
          for (const part of chunkString(turn.thoughtText, CHUNK_SIZE)) {
            if (aborted.value) break;
            send("thought_delta", { type: "thought_delta", text: part });
            await sleep(BETWEEN_CHUNK_MS / speed);
          }
        }
        if (turn.assistantText) {
          for (const part of chunkString(turn.assistantText, CHUNK_SIZE)) {
            if (aborted.value) break;
            send("answer_delta", { type: "answer_delta", text: part });
            await sleep(BETWEEN_CHUNK_MS / speed);
          }
        }
        send("turn_end", {
          type: "turn_end",
          turnId: turn.id,
          finishReason: turn.finishReason ?? "STOP",
        });
      }

      send("conversation_end", { type: "conversation_end", id: conversation.id });
      controller.close();
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
