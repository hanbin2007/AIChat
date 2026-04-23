import path from "node:path";
import { promises as fs } from "node:fs";
import { describe, expect, it, beforeEach } from "vitest";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "@/lib/store/persistence";
import { config } from "@/lib/config";
import { resetState } from "../helpers";

describe("persistence", () => {
  beforeEach(resetState);

  it("returns the fallback when file is missing", async () => {
    const out = await readJsonFile(path.join(config.dataDir, "missing.json"), { fallback: true });
    expect(out).toEqual({ fallback: true });
  });

  it("atomic write then read round-trips", async () => {
    const file = path.join(config.dataDir, "state.json");
    await writeJsonFileAtomic(file, { a: 1, b: [1, 2, 3] });
    const data = await readJsonFile(file, {});
    expect(data).toEqual({ a: 1, b: [1, 2, 3] });
  });

  it("writes do not leave tmp files around on success", async () => {
    const file = path.join(config.dataDir, "clean.json");
    await writeJsonFileAtomic(file, { ok: true });
    const entries = await fs.readdir(config.dataDir);
    expect(entries.filter((e) => e.includes(".tmp"))).toEqual([]);
  });

  it("WriteQueue serialises concurrent mutations", async () => {
    const queue = new WriteQueue();
    const order: number[] = [];
    const tasks = [10, 5, 2].map((delay, i) =>
      queue.run(async () => {
        await new Promise((r) => setTimeout(r, delay));
        order.push(i);
      }),
    );
    await Promise.all(tasks);
    expect(order).toEqual([0, 1, 2]);
  });

  it("WriteQueue keeps running after a failure", async () => {
    const queue = new WriteQueue();
    await expect(queue.run(async () => { throw new Error("boom"); })).rejects.toThrow("boom");
    const result = await queue.run(async () => 42);
    expect(result).toBe(42);
  });
});
