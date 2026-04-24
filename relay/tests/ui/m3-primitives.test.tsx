import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

afterEach(cleanup);
import { Button } from "@/components/m3/button";
import { Chip } from "@/components/m3/chip";
import { Switch } from "@/components/m3/switch";
import { Slider } from "@/components/m3/slider";
import { Segmented } from "@/components/m3/segmented";
import { Banner } from "@/components/m3/banner";
import { Dialog } from "@/components/m3/dialog";
import { Badge } from "@/components/m3/badge";

describe("M3 Button", () => {
  it("invokes onClick when pressed", async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Save</Button>);
    await userEvent.click(screen.getByRole("button", { name: /save/i }));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it("suppresses clicks when loading", async () => {
    const onClick = vi.fn();
    render(<Button loading onClick={onClick}>Save</Button>);
    await userEvent.click(screen.getByRole("button"));
    expect(onClick).not.toHaveBeenCalled();
  });

  it("renders a leading icon glyph", () => {
    render(<Button icon="add">Add</Button>);
    expect(screen.getByText("add")).toBeDefined();
  });
});

describe("M3 Chip", () => {
  it("exposes aria-pressed when in filter mode", () => {
    render(<Chip selected>On</Chip>);
    expect(screen.getByRole("button").getAttribute("aria-pressed")).toBe("true");
  });

  it("fires onRemove separately from onClick", async () => {
    const onClick = vi.fn();
    const onRemove = vi.fn();
    render(
      <Chip variant="input" onRemove={onRemove} onClick={onClick}>
        tag
      </Chip>,
    );
    const remove = screen.getByRole("button", { name: /remove/i });
    fireEvent.click(remove);
    expect(onRemove).toHaveBeenCalledOnce();
    expect(onClick).not.toHaveBeenCalled();
  });
});

describe("M3 Switch", () => {
  it("reflects controlled checked state + fires onChange", async () => {
    const onChange = vi.fn();
    const { rerender } = render(<Switch label="Enable" checked={false} onChange={onChange} />);
    const input = screen.getByRole("checkbox") as HTMLInputElement;
    await userEvent.click(input);
    expect(onChange).toHaveBeenCalled();
    rerender(<Switch label="Enable" checked={true} onChange={onChange} />);
    expect((screen.getByRole("checkbox") as HTMLInputElement).checked).toBe(true);
  });
});

describe("M3 Slider", () => {
  it("parses numeric range input and bubbles changes", () => {
    const onChange = vi.fn();
    render(<Slider label="Volume" value={10} min={0} max={100} onChange={onChange} />);
    const range = screen.getByRole("slider") as HTMLInputElement;
    fireEvent.change(range, { target: { value: "42" } });
    expect(onChange).toHaveBeenCalledWith(42);
  });
});

describe("M3 Segmented", () => {
  it("switches selection on click", async () => {
    const onChange = vi.fn();
    render(
      <Segmented
        value="a"
        onChange={onChange}
        options={[{ value: "a", label: "A" }, { value: "b", label: "B" }]}
      />,
    );
    await userEvent.click(screen.getByRole("tab", { name: "B" }));
    expect(onChange).toHaveBeenCalledWith("b");
  });
});

describe("M3 Banner", () => {
  it("renders title + children + action slot", () => {
    render(
      <Banner tone="warn" title="Careful" actions={<button>Act</button>}>
        Heads-up
      </Banner>,
    );
    expect(screen.getByText("Careful")).toBeDefined();
    expect(screen.getByText("Heads-up")).toBeDefined();
    expect(screen.getByRole("button", { name: "Act" })).toBeDefined();
  });
});

describe("M3 Dialog", () => {
  it("does not render anything when closed", () => {
    const { container } = render(<Dialog open={false} onClose={() => {}} title="x" />);
    expect(container.querySelector("[role='dialog']")).toBeNull();
  });

  it("invokes onClose when Escape is pressed", () => {
    const onClose = vi.fn();
    render(<Dialog open onClose={onClose} title="x">body</Dialog>);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(onClose).toHaveBeenCalled();
  });
});

describe("M3 Badge", () => {
  it("maps tone to the correct surface class", () => {
    render(<Badge tone="error">oops</Badge>);
    const el = screen.getByText("oops");
    expect(el.className).toMatch(/error-container/);
  });
});
