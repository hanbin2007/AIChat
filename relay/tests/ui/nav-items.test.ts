import { describe, it, expect } from "vitest";
import { NAV_ITEMS, SECTION_LABELS } from "@/components/shell/nav-items";

describe("NAV_ITEMS", () => {
  it("has 10 entries covering ⌘1–⌘0", () => {
    expect(NAV_ITEMS).toHaveLength(10);
    const shortcuts = NAV_ITEMS.map((i) => i.shortcut).sort();
    expect(shortcuts).toEqual(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]);
  });

  it("every nav item has a unique href starting with /", () => {
    const hrefs = NAV_ITEMS.map((i) => i.href);
    expect(new Set(hrefs).size).toBe(hrefs.length);
    for (const h of hrefs) expect(h.startsWith("/")).toBe(true);
  });

  it("every nav item belongs to a known section with a label", () => {
    for (const item of NAV_ITEMS) {
      expect(SECTION_LABELS[item.section]).toBeTruthy();
    }
  });

  it("groups: 3 core, 3 billing, 4 system", () => {
    const counts = { core: 0, billing: 0, system: 0 } as Record<string, number>;
    for (const i of NAV_ITEMS) counts[i.section] += 1;
    expect(counts).toEqual({ core: 3, billing: 3, system: 4 });
  });
});
