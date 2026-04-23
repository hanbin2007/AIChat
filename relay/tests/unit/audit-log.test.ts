import { beforeEach, describe, expect, it } from "vitest";
import { auditLog } from "@/lib/store/audit-log";
import { resetState } from "../helpers";

describe("auditLog", () => {
  beforeEach(resetState);

  it("seeds the first entry with GENESIS prevHash", async () => {
    const entry = await auditLog().append({ actor: "alice", role: "operator", action: "init" });
    expect(entry.prevHash).toBe("GENESIS");
    expect(entry.hash.length).toBeGreaterThan(10);
  });

  it("chains hashes across entries", async () => {
    const a = await auditLog().append({ actor: "alice", role: "operator", action: "a" });
    const b = await auditLog().append({ actor: "alice", role: "operator", action: "b" });
    const c = await auditLog().append({ actor: "alice", role: "operator", action: "c" });
    expect(b.prevHash).toBe(a.hash);
    expect(c.prevHash).toBe(b.hash);
  });

  it("list returns entries in reverse-chronological order", async () => {
    await auditLog().append({ actor: "x", role: "operator", action: "first" });
    await auditLog().append({ actor: "x", role: "operator", action: "second" });
    const list = await auditLog().list();
    expect(list[0].action).toBe("second");
    expect(list[1].action).toBe("first");
  });

  it("different payloads yield different hashes (tamper detection)", async () => {
    const a = await auditLog().append({ actor: "x", role: "operator", action: "a", target: "x" });
    const b = await auditLog().append({ actor: "x", role: "operator", action: "a", target: "y" });
    expect(a.hash).not.toBe(b.hash);
  });
});
