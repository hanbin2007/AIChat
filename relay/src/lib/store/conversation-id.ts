/**
 * Stable conversation-id derivation. Shared between conversation list
 * reconstruction (consumes activity entries) and the request log
 * (so truncation can exempt pinned conversations).
 */

import { createHash } from "node:crypto";
import type { ActivityEntry } from "./request-log";

export function conversationKeyForEntry(entry: ActivityEntry): string {
  if (entry.conversationID) return entry.conversationID;
  const body = (entry.requestBody as Record<string, unknown> | undefined) ?? {};
  const messages = Array.isArray(body.messages) ? (body.messages as Record<string, unknown>[]) : [];
  const fingerprint = messages.slice(0, 3).map((m) => String(m.text ?? "")).join("");
  const hash = createHash("sha1").update(`${entry.deviceID ?? ""}|${fingerprint}`).digest("hex");
  return `auto-${hash.slice(0, 16)}`;
}
