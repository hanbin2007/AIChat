import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

afterEach(cleanup);

import { KpiCard } from "@/components/kpi-card";

describe("KpiCard", () => {
  it("renders the label and value", () => {
    render(<KpiCard label="Active users" value="1,234" />);
    expect(screen.getByText("Active users")).toBeDefined();
    expect(screen.getByText("1,234")).toBeDefined();
  });

  it("renders delta with the neutral tone class by default", () => {
    render(<KpiCard label="x" value="42" delta="+1%" />);
    const delta = screen.getByText("+1%");
    expect(delta.className).toMatch(/text-on-surface-variant/);
  });

  it("applies positive tone styling for positive deltas", () => {
    render(<KpiCard label="x" value="42" delta="+5" tone="positive" />);
    const delta = screen.getByText("+5");
    expect(delta.className).toMatch(/text-primary/);
  });

  it("applies negative tone styling for negative deltas", () => {
    render(<KpiCard label="x" value="42" delta="-7" tone="negative" />);
    const delta = screen.getByText("-7");
    expect(delta.className).toMatch(/text-error/);
  });

  it("renders the helper text when provided", () => {
    render(<KpiCard label="x" value="42" helper="vs last week" />);
    expect(screen.getByText("vs last week")).toBeDefined();
  });

  it("does not render a sparkline when the data has fewer than two points", () => {
    const { container } = render(<KpiCard label="x" value="42" spark={[1]} />);
    expect(container.querySelector("svg")).toBeNull();
  });

  it("renders a sparkline svg when the spark series has multiple points", () => {
    const { container } = render(<KpiCard label="x" value="42" spark={[1, 4, 2, 8]} />);
    const svg = container.querySelector("svg");
    expect(svg).not.toBeNull();
    const path = container.querySelector("path");
    expect(path?.getAttribute("d")).toMatch(/^M0\.0/);
    // Sanity: there should be one M and three L commands for 4 points.
    const d = path?.getAttribute("d") ?? "";
    expect((d.match(/L/g) ?? []).length).toBe(3);
  });

  it("handles all-zero spark series without dividing by zero", () => {
    const { container } = render(<KpiCard label="x" value="0" spark={[0, 0, 0]} />);
    const path = container.querySelector("path");
    expect(path?.getAttribute("d")).toBeDefined();
  });
});
