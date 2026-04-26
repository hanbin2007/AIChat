/**
 * Conversation pin store. Pinned conversations are exempt from request-log
 * truncation so operators can keep notable transcripts indefinitely. The
 * data is a simple set of conversation IDs persisted as JSON.
 */

import path from "node:path";
import { config } from "@/lib/config";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "./persistence";

const FILE = () => path.join(config.dataDir, "conversation-pins.json");

interface State {
  pinned: string[];
  notes: Record<string, string>;
}

class ConversationPins {
  private state: State = { pinned: [], notes: {} };
  private loaded = false;
  private queue = new WriteQueue();

  async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    this.state = await readJsonFile(FILE(), { pinned: [], notes: {} });
    this.loaded = true;
  }

  async list(): Promise<string[]> {
    await this.ensureLoaded();
    return [...this.state.pinned];
  }

  async isPinned(id: string): Promise<boolean> {
    await this.ensureLoaded();
    return this.state.pinned.includes(id);
  }

  async noteFor(id: string): Promise<string | undefined> {
    await this.ensureLoaded();
    return this.state.notes[id];
  }

  async pin(id: string, note?: string): Promise<void> {
    await this.queue.run(async () => {
      await this.ensureLoaded();
      if (!this.state.pinned.includes(id)) this.state.pinned.push(id);
      if (note !== undefined) this.state.notes[id] = note;
      await writeJsonFileAtomic(FILE(), this.state);
    });
  }

  async unpin(id: string): Promise<void> {
    await this.queue.run(async () => {
      await this.ensureLoaded();
      this.state.pinned = this.state.pinned.filter((x) => x !== id);
      delete this.state.notes[id];
      await writeJsonFileAtomic(FILE(), this.state);
    });
  }
}

declare global {
  // eslint-disable-next-line no-var
  var __conversationPins: ConversationPins | undefined;
}

export function conversationPins(): ConversationPins {
  if (!globalThis.__conversationPins) globalThis.__conversationPins = new ConversationPins();
  return globalThis.__conversationPins;
}
