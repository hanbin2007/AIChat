import { afterEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

afterEach(cleanup);

import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/m3/card";
import { Fab } from "@/components/m3/fab";
import { SnackbarProvider, useSnackbar } from "@/components/m3/snackbar";
import { Tabs } from "@/components/m3/tabs";
import { TextField } from "@/components/m3/text-field";
import * as M3 from "@/components/m3";

describe("M3 Card", () => {
  it("renders header, title, description, and content children", () => {
    render(
      <Card>
        <CardHeader>
          <CardTitle>Hello</CardTitle>
          <CardDescription>Subtitle here</CardDescription>
        </CardHeader>
        <CardContent>Body text</CardContent>
      </Card>,
    );
    expect(screen.getByText("Hello")).toBeDefined();
    expect(screen.getByText("Subtitle here")).toBeDefined();
    expect(screen.getByText("Body text")).toBeDefined();
  });

  it("applies the elevated variant class", () => {
    const { container } = render(<Card variant="elevated">x</Card>);
    expect(container.firstElementChild?.className).toMatch(/surface-container-low/);
  });

  it("applies the filled variant class", () => {
    const { container } = render(<Card variant="filled">x</Card>);
    expect(container.firstElementChild?.className).toMatch(/surface-container-highest/);
  });

  it("applies the outlined variant by default", () => {
    const { container } = render(<Card>x</Card>);
    expect(container.firstElementChild?.className).toMatch(/border-outline-variant/);
  });

  it("merges user className with built-in classes", () => {
    const { container } = render(<Card className="my-extra">x</Card>);
    expect(container.firstElementChild?.className).toMatch(/my-extra/);
  });
});

describe("M3 Fab", () => {
  it("renders an icon-only button (no label)", () => {
    render(<Fab icon="add" aria-label="Add" />);
    const btn = screen.getByRole("button", { name: /add/i });
    expect(btn).toBeDefined();
    expect(btn.className).toMatch(/aspect-square/);
  });

  it("renders extended FAB with label text", () => {
    render(<Fab icon="add" label="Compose" />);
    expect(screen.getByText("Compose")).toBeDefined();
    const btn = screen.getByRole("button");
    expect(btn.className).not.toMatch(/aspect-square/);
  });

  it("invokes onClick", async () => {
    const onClick = vi.fn();
    render(<Fab icon="add" label="Go" onClick={onClick} />);
    await userEvent.click(screen.getByRole("button", { name: /go/i }));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it("supports the small size", () => {
    const { container } = render(<Fab icon="add" size="sm" aria-label="Small" />);
    expect(container.querySelector("button")?.className).toMatch(/h-10/);
  });

  it("supports the large size", () => {
    const { container } = render(<Fab icon="add" size="lg" aria-label="Big" />);
    expect(container.querySelector("button")?.className).toMatch(/h-24/);
  });
});

describe("M3 Snackbar", () => {
  function Trigger({ withAction = false }: { withAction?: boolean }) {
    const { push } = useSnackbar();
    return (
      <button
        onClick={() =>
          push({
            message: "Saved",
            ...(withAction
              ? { action: { label: "Undo", onClick: () => undefined } }
              : {}),
          })
        }
      >
        do
      </button>
    );
  }

  it("queues a snack and removes it after the timeout", async () => {
    vi.useFakeTimers();
    try {
      render(
        <SnackbarProvider>
          <Trigger />
        </SnackbarProvider>,
      );
      await act(async () => {
        fireEvent.click(screen.getByRole("button", { name: /do/i }));
      });
      expect(screen.getByText("Saved")).toBeDefined();
      await act(async () => {
        vi.advanceTimersByTime(5001);
      });
      expect(screen.queryByText("Saved")).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it("renders the action label and fires its onClick", async () => {
    const onActionClick = vi.fn();
    function ActionTrigger() {
      const { push } = useSnackbar();
      return (
        <button
          onClick={() =>
            push({ message: "Hi", action: { label: "Undo", onClick: onActionClick } })
          }
        >
          push
        </button>
      );
    }
    render(
      <SnackbarProvider>
        <ActionTrigger />
      </SnackbarProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: /push/i }));
    const undo = screen.getByRole("button", { name: /undo/i });
    fireEvent.click(undo);
    expect(onActionClick).toHaveBeenCalledOnce();
  });

  it("throws when used outside the provider", () => {
    function Bad() {
      useSnackbar();
      return null;
    }
    // React renders an error log to console — silence it for this test.
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    expect(() => render(<Bad />)).toThrow(/SnackbarProvider/);
    errSpy.mockRestore();
  });
});

describe("M3 Tabs", () => {
  it("invokes onChange with the new value when a tab is clicked", async () => {
    const onChange = vi.fn();
    render(
      <Tabs
        value="a"
        onChange={onChange}
        options={[
          { value: "a", label: "Alpha" },
          { value: "b", label: "Beta" },
        ]}
      />,
    );
    await userEvent.click(screen.getByRole("tab", { name: "Beta" }));
    expect(onChange).toHaveBeenCalledWith("b");
  });

  it("marks the current tab as selected", () => {
    render(
      <Tabs
        value="b"
        onChange={() => undefined}
        options={[
          { value: "a", label: "Alpha" },
          { value: "b", label: "Beta" },
        ]}
      />,
    );
    expect(screen.getByRole("tab", { name: "Alpha" }).getAttribute("aria-selected")).toBe(
      "false",
    );
    expect(screen.getByRole("tab", { name: "Beta" }).getAttribute("aria-selected")).toBe(
      "true",
    );
  });

  it("uses secondary variant styling when requested", () => {
    render(
      <Tabs
        variant="secondary"
        value="a"
        onChange={() => undefined}
        options={[{ value: "a", label: "Alpha" }]}
      />,
    );
    const active = screen.getByRole("tab", { name: "Alpha" });
    expect(active.className).toMatch(/text-on-surface/);
  });
});

describe("M3 TextField", () => {
  it("renders a label associated with the input via htmlFor", () => {
    render(<TextField label="Name" placeholder="enter name" />);
    const input = screen.getByPlaceholderText("enter name") as HTMLInputElement;
    const label = screen.getByText("Name") as HTMLLabelElement;
    expect(label.htmlFor).toBe(input.id);
    expect(input.id).toBeTruthy();
  });

  it("uses an explicit id when provided", () => {
    render(<TextField label="Email" id="email-field" />);
    const input = screen.getByLabelText("Email") as HTMLInputElement;
    expect(input.id).toBe("email-field");
  });

  it("fires onChange when the user types", async () => {
    const onChange = vi.fn();
    render(<TextField label="Name" onChange={onChange} />);
    const input = screen.getByLabelText("Name");
    await userEvent.type(input, "ab");
    expect(onChange).toHaveBeenCalled();
  });

  it("renders supporting text when no error is set", () => {
    render(<TextField label="x" supporting="please fill in" />);
    expect(screen.getByText("please fill in")).toBeDefined();
  });

  it("renders the error message in place of supporting text", () => {
    render(<TextField label="x" supporting="hint" error="bad input" />);
    expect(screen.getByText("bad input")).toBeDefined();
    expect(screen.queryByText("hint")).toBeNull();
  });

  it("renders a leading glyph", () => {
    render(<TextField label="x" leading="search" />);
    expect(screen.getByText("search")).toBeDefined();
  });

  it("renders the trailing button and fires onTrailingClick", () => {
    const onTrailingClick = vi.fn();
    render(<TextField label="x" trailing="close" onTrailingClick={onTrailingClick} />);
    const trailingBtn = screen.getByRole("button");
    fireEvent.click(trailingBtn);
    expect(onTrailingClick).toHaveBeenCalledOnce();
  });

  it("supports the filled variant", () => {
    const { container } = render(<TextField label="x" variant="filled" />);
    const wrapper = container.querySelector("input")?.parentElement;
    expect(wrapper?.className).toMatch(/surface-container-highest/);
  });
});

describe("M3 barrel export", () => {
  it("re-exports the expected primitives", () => {
    expect(M3.Button).toBeDefined();
    expect(M3.IconButton).toBeDefined();
    expect(M3.Fab).toBeDefined();
    expect(M3.Card).toBeDefined();
    expect(M3.CardHeader).toBeDefined();
    expect(M3.CardTitle).toBeDefined();
    expect(M3.CardDescription).toBeDefined();
    expect(M3.CardContent).toBeDefined();
    expect(M3.Chip).toBeDefined();
    expect(M3.TextField).toBeDefined();
    expect(M3.Switch).toBeDefined();
    expect(M3.Slider).toBeDefined();
    expect(M3.Segmented).toBeDefined();
    expect(M3.Tabs).toBeDefined();
    expect(M3.Dialog).toBeDefined();
    expect(M3.Banner).toBeDefined();
    expect(M3.SnackbarProvider).toBeDefined();
    expect(M3.useSnackbar).toBeDefined();
    expect(M3.Badge).toBeDefined();
    expect(M3.Icon).toBeDefined();
  });
});
