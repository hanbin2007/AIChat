import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

afterEach(cleanup);

import { LaunchChecklist, type ChecklistItem } from "@/components/launch-checklist";

const partial: ChecklistItem[] = [
  { id: "a", label: "Configure Gemini", description: "Set GEMINI_API_KEY", done: true, href: "/settings" },
  { id: "b", label: "Issue token", description: "Create a bearer token", done: false, href: "/tokens" },
  { id: "c", label: "Verify", description: "Smoke test", done: false },
];

const allDone: ChecklistItem[] = partial.map((p) => ({ ...p, done: true }));

describe("LaunchChecklist", () => {
  it("shows the partial-progress headline and counter", () => {
    render(<LaunchChecklist items={partial} />);
    expect(screen.getByText("启动清单")).toBeDefined();
    expect(screen.getByText("完成 1/3 项即可正式上线")).toBeDefined();
  });

  it("renders one link per item, with the right hrefs", () => {
    render(<LaunchChecklist items={partial} />);
    const links = screen.getAllByRole("link");
    expect(links).toHaveLength(3);
    expect(links[0].getAttribute("href")).toBe("/settings");
    expect(links[1].getAttribute("href")).toBe("/tokens");
    // Items without an href fall back to "#"
    expect(links[2].getAttribute("href")).toBe("#");
  });

  it("renders the description text for every item", () => {
    render(<LaunchChecklist items={partial} />);
    for (const item of partial) {
      expect(screen.getByText(item.description)).toBeDefined();
      expect(screen.getByText(item.label)).toBeDefined();
    }
  });

  it("renders the all-done headline and 'Ready to serve' label when fully complete", () => {
    render(<LaunchChecklist items={allDone} />);
    expect(screen.getByText("Ready to serve")).toBeDefined();
    expect(screen.getByText("所有关键配置已就绪")).toBeDefined();
  });

  it("renders a numeric step indicator for unfinished items", () => {
    render(<LaunchChecklist items={partial} />);
    // Items b and c are unfinished → expect indices 2 and 3 visible.
    expect(screen.getByText("2")).toBeDefined();
    expect(screen.getByText("3")).toBeDefined();
  });
});
