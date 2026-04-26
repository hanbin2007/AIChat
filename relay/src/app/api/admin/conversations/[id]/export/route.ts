import { requireAdmin } from "@/lib/auth/admin-guard";
import { getConversation, type Conversation } from "@/lib/store/conversations";
import { errorResponse } from "@/lib/api/error";

export const runtime = "nodejs";

function toMarkdown(c: Conversation): string {
  const lines: string[] = [];
  lines.push(`# ${c.title}`, "");
  lines.push(
    `> account: \`${c.accountID ?? "—"}\` · device: \`${c.deviceID ?? "—"}\` (${c.devicePlatform ?? "?"}) · ${c.turnCount} turns · ${c.totalCredits} credits`,
    "",
    `> from ${new Date(c.firstAt).toLocaleString()} to ${new Date(c.lastAt).toLocaleString()}`,
    "",
  );
  for (const turn of c.turns) {
    if (turn.userText) {
      lines.push(`### 🧑 User · ${new Date(turn.timestamp).toLocaleString()}`);
      lines.push("", turn.userText, "");
    }
    if (turn.thoughtText) {
      lines.push(`<details><summary>💭 Thought (${turn.thoughtText.length} chars)</summary>`);
      lines.push("", "```", turn.thoughtText, "```", "</details>", "");
    }
    if (turn.assistantText) {
      lines.push(
        `### 🤖 Assistant · ${turn.modelID ?? "?"} · ${turn.inputTokens ?? 0}→${turn.outputTokens ?? 0} tokens`,
      );
      lines.push("", turn.assistantText, "");
    }
    if (turn.error) lines.push(`> ⚠️ ${turn.error}`, "");
    lines.push("---", "");
  }
  return lines.join("\n");
}

function toTranscript(c: Conversation): string {
  const out: string[] = [];
  for (const turn of c.turns) {
    if (turn.userText) out.push(`User: ${turn.userText}`);
    if (turn.assistantText) out.push(`Assistant: ${turn.assistantText}`);
  }
  return out.join("\n\n");
}

export async function GET(req: Request, context: { params: Promise<{ id: string }> }) {
  const guard = await requireAdmin();
  if (!guard.ok) return guard.response;
  const { id } = await context.params;
  const conversation = await getConversation(id);
  if (!conversation) return errorResponse(404, "Conversation not found.");
  const url = new URL(req.url);
  const format = (url.searchParams.get("format") ?? "json").toLowerCase();
  const safeId = id.replace(/[^a-zA-Z0-9_-]/g, "_");

  if (format === "markdown" || format === "md") {
    return new Response(toMarkdown(conversation), {
      status: 200,
      headers: {
        "Content-Type": "text/markdown; charset=utf-8",
        "Content-Disposition": `attachment; filename="conversation-${safeId}.md"`,
      },
    });
  }
  if (format === "transcript" || format === "txt") {
    return new Response(toTranscript(conversation), {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Content-Disposition": `attachment; filename="conversation-${safeId}.txt"`,
      },
    });
  }
  return new Response(JSON.stringify(conversation, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="conversation-${safeId}.json"`,
    },
  });
}
