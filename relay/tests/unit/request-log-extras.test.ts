import { beforeEach, describe, expect, it } from "vitest";
import { requestLog } from "@/lib/store/request-log";
import { resetState } from "../helpers";

describe("requestLog buffer", () => {
  beforeEach(resetState);

  it("listDebug returns recorded debug entries newest-first", async () => {
    const log = requestLog();
    await log.recordDebug({
      id: "d1",
      timestamp: new Date(Date.now() - 1000).toISOString(),
      source: "relay",
      kind: "request",
      title: "first",
    });
    await log.recordDebug({
      id: "d2",
      timestamp: new Date().toISOString(),
      source: "upstream",
      kind: "response",
      title: "second",
    });
    const list = await log.listDebug();
    expect(list.map((e) => e.id)).toEqual(["d2", "d1"]);
  });

  it("clearActivity wipes the activity buffer", async () => {
    const log = requestLog();
    await log.recordActivity({
      id: "a1",
      timestamp: new Date().toISOString(),
      level: "info",
      category: "request",
      message: "x",
    });
    expect((await log.listActivity()).length).toBe(1);
    await log.clearActivity();
    expect((await log.listActivity()).length).toBe(0);
  });

  it("clearDebug wipes the debug buffer", async () => {
    const log = requestLog();
    await log.recordDebug({
      id: "d1",
      timestamp: new Date().toISOString(),
      source: "relay",
      kind: "event",
      title: "x",
    });
    expect((await log.listDebug()).length).toBe(1);
    await log.clearDebug();
    expect((await log.listDebug()).length).toBe(0);
  });

  it("configureCaps trims oversized buffers", async () => {
    const log = requestLog();
    for (let i = 0; i < 10; i++) {
      await log.recordActivity({
        id: `a${i}`,
        timestamp: new Date().toISOString(),
        level: "info",
        category: "request",
        message: String(i),
      });
    }
    log.configureCaps(3, 3);
    const list = await log.listActivity();
    // newest-first; cap of 3 keeps the last three (a7, a8, a9).
    expect(list.map((e) => e.id)).toEqual(["a9", "a8", "a7"]);
  });
});
