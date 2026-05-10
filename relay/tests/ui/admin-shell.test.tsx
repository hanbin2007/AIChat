import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// next/navigation must be mocked BEFORE the component is imported.
const pushMock = vi.fn();
const refreshMock = vi.fn();
const pathnameRef = { current: "/dashboard" };

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: refreshMock }),
  usePathname: () => pathnameRef.current,
}));

// next/link → forward to a plain anchor for happy-dom.
vi.mock("next/link", () => ({
  __esModule: true,
  default: ({
    href,
    children,
    ...rest
  }: {
    href: string;
    children: React.ReactNode;
  } & Record<string, unknown>) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));

import * as React from "react";
import { AdminShell, NAV_ITEMS } from "@/components/admin-shell";

beforeEach(() => {
  pushMock.mockReset();
  refreshMock.mockReset();
  pathnameRef.current = "/dashboard";
  document.documentElement.classList.remove("dark");
  localStorage.clear();
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => new Response(null, { status: 204 })),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("AdminShell", () => {
  it("renders the title, breadcrumb, and child content", () => {
    render(
      <AdminShell title="My Page" breadcrumb={["Admin", "Section"]}>
        <div>main content</div>
      </AdminShell>,
    );
    expect(screen.getByRole("heading", { name: "My Page" })).toBeDefined();
    expect(screen.getByText("Admin")).toBeDefined();
    expect(screen.getByText("Section")).toBeDefined();
    expect(screen.getByText("main content")).toBeDefined();
  });

  it("renders the navigation rail with one link per NAV_ITEM", () => {
    render(<AdminShell title="x">child</AdminShell>);
    for (const item of NAV_ITEMS) {
      const link = screen.getByRole("link", { name: new RegExp(item.label) });
      expect(link.getAttribute("href")).toBe(item.href);
    }
  });

  it("expands the rail on mouse enter and collapses on mouse leave", async () => {
    const { container } = render(<AdminShell title="x">c</AdminShell>);
    const aside = container.querySelector("aside")!;
    expect(aside.className).toMatch(/w-20/);
    fireEvent.mouseEnter(aside);
    expect(aside.className).toMatch(/w-64/);
    fireEvent.mouseLeave(aside);
    expect(aside.className).toMatch(/w-20/);
  });

  it("opens the command palette on Cmd/Ctrl+K and closes it on Escape", async () => {
    render(<AdminShell title="x">c</AdminShell>);
    expect(screen.queryByPlaceholderText(/搜索页面/)).toBeNull();
    fireEvent.keyDown(document, { key: "k", ctrlKey: true });
    expect(screen.getByPlaceholderText(/搜索页面/)).toBeDefined();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByPlaceholderText(/搜索页面/)).toBeNull();
  });

  it("opens the palette via the header search button and closes when the backdrop is clicked", async () => {
    const { container } = render(<AdminShell title="x">c</AdminShell>);
    const searchBtn = screen.getByText("全局搜索").closest("button")!;
    fireEvent.click(searchBtn);
    expect(screen.getByPlaceholderText(/搜索页面/)).toBeDefined();
    // The backdrop is the fixed inset wrapper.
    const backdrop = container.querySelector(".fixed.inset-0")!;
    fireEvent.click(backdrop);
    expect(screen.queryByPlaceholderText(/搜索页面/)).toBeNull();
  });

  it("filters palette matches as the user types and navigates on click", async () => {
    render(<AdminShell title="x">c</AdminShell>);
    fireEvent.keyDown(document, { key: "k", metaKey: true });
    const input = screen.getByPlaceholderText(/搜索页面/) as HTMLInputElement;
    await userEvent.type(input, "Billing");
    // After filter, only Billing Studio should be visible inside the palette list.
    const billingButton = screen.getByRole("button", { name: /Billing Studio/i });
    fireEvent.click(billingButton);
    expect(pushMock).toHaveBeenCalledWith("/billing");
  });

  it("clicking inside the palette dialog does not close it", () => {
    render(<AdminShell title="x">c</AdminShell>);
    fireEvent.keyDown(document, { key: "k", ctrlKey: true });
    const dialog = screen.getByPlaceholderText(/搜索页面/).closest("div")!;
    fireEvent.click(dialog);
    expect(screen.getByPlaceholderText(/搜索页面/)).toBeDefined();
  });

  it("Cmd+<digit> navigates to the matching nav item", () => {
    render(<AdminShell title="x">c</AdminShell>);
    fireEvent.keyDown(document, { key: "2", metaKey: true });
    expect(pushMock).toHaveBeenCalledWith("/requests");
  });

  it("ignores unmapped Cmd+digit shortcuts", () => {
    render(<AdminShell title="x">c</AdminShell>);
    pushMock.mockClear();
    fireEvent.keyDown(document, { key: "x", metaKey: true });
    expect(pushMock).not.toHaveBeenCalled();
  });

  it("toggles the dark class on the html element and persists the choice", async () => {
    render(<AdminShell title="x">c</AdminShell>);
    const themeBtn = screen.getByLabelText("切换主题");
    fireEvent.click(themeBtn);
    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(localStorage.getItem("relay_theme")).toBe("dark");
    fireEvent.click(themeBtn);
    expect(document.documentElement.classList.contains("dark")).toBe(false);
    expect(localStorage.getItem("relay_theme")).toBe("light");
  });

  it("logout posts to /api/admin/logout and routes to /login", async () => {
    render(<AdminShell title="x">c</AdminShell>);
    const logoutBtn = screen.getByLabelText("注销");
    fireEvent.click(logoutBtn);
    // Allow the logout async to resolve.
    await Promise.resolve();
    await Promise.resolve();
    const fetchMock = (globalThis as { fetch: ReturnType<typeof vi.fn> }).fetch;
    expect(fetchMock).toHaveBeenCalledWith("/api/admin/logout", { method: "POST" });
    expect(pushMock).toHaveBeenCalledWith("/login");
  });

  it("highlights the active link based on pathname startsWith match", () => {
    pathnameRef.current = "/billing/plans";
    render(<AdminShell title="x">c</AdminShell>);
    const billingLink = screen.getByRole("link", { name: /Billing Studio/i });
    expect(billingLink.className).toMatch(/secondary-container/);
  });

  it("renders header actions in the actions slot", () => {
    render(
      <AdminShell title="x" actions={<button>Save</button>}>
        c
      </AdminShell>,
    );
    expect(screen.getByRole("button", { name: "Save" })).toBeDefined();
  });

  it("seeds dark state from the html dark class on mount", () => {
    document.documentElement.classList.add("dark");
    render(<AdminShell title="x">c</AdminShell>);
    // When dark on mount, the toggle button shows the light_mode glyph.
    const themeBtn = screen.getByLabelText("切换主题");
    expect(themeBtn.textContent).toMatch(/light_mode/);
  });
});
