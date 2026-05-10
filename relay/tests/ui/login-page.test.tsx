import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

const pushMock = vi.fn();
const refreshMock = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: refreshMock }),
  usePathname: () => "/login",
}));

import LoginPage from "@/app/login/page";

beforeEach(() => {
  pushMock.mockReset();
  refreshMock.mockReset();
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("LoginPage", () => {
  it("renders the login form with username and password fields", () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 200 })));
    render(<LoginPage />);
    expect(screen.getByLabelText("用户名")).toBeDefined();
    expect(screen.getByLabelText("密码")).toBeDefined();
    expect(screen.getByRole("button", { name: /登录/ })).toBeDefined();
    expect(screen.getByRole("link", { name: /前往初始化/ }).getAttribute("href")).toBe("/setup");
  });

  it("submits credentials and navigates to /dashboard on success", async () => {
    const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<LoginPage />);
    await userEvent.type(screen.getByLabelText("用户名"), "alice");
    await userEvent.type(screen.getByLabelText("密码"), "secret123");
    fireEvent.click(screen.getByRole("button", { name: /登录/ }));
    await waitFor(() => expect(pushMock).toHaveBeenCalledWith("/dashboard"));
    expect(refreshMock).toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/admin/login",
      expect.objectContaining({
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: "alice", password: "secret123" }),
      }),
    );
  });

  it("shows the server-supplied error message on a 401 response", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(JSON.stringify({ message: "用户名或密码错误" }), {
            status: 401,
            headers: { "Content-Type": "application/json" },
          }),
      ),
    );
    render(<LoginPage />);
    await userEvent.type(screen.getByLabelText("用户名"), "bob");
    await userEvent.type(screen.getByLabelText("密码"), "wrong");
    fireEvent.click(screen.getByRole("button", { name: /登录/ }));
    await waitFor(() => expect(screen.getByText("用户名或密码错误")).toBeDefined());
    expect(pushMock).not.toHaveBeenCalled();
  });

  it("falls back to a default error message when the body is not JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("oops", { status: 500 })),
    );
    render(<LoginPage />);
    await userEvent.type(screen.getByLabelText("用户名"), "x");
    await userEvent.type(screen.getByLabelText("密码"), "y");
    fireEvent.click(screen.getByRole("button", { name: /登录/ }));
    await waitFor(() => expect(screen.getByText("登录失败")).toBeDefined());
  });
});
