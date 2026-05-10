import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

const pushMock = vi.fn();
const refreshMock = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: refreshMock }),
  usePathname: () => "/setup",
}));

import SetupForm from "@/app/setup/setup-form";

beforeEach(() => {
  pushMock.mockReset();
  refreshMock.mockReset();
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("SetupForm", () => {
  it("starts on step 0 with a welcome message and a Start button", () => {
    render(<SetupForm />);
    expect(screen.getByText(/欢迎使用 AIChat Relay/)).toBeDefined();
    expect(screen.getByRole("button", { name: /开始/ })).toBeDefined();
  });

  it("advances to step 1 when Start is clicked", async () => {
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    expect(screen.getByLabelText("管理员用户名")).toBeDefined();
    expect(screen.getByLabelText("管理员密码")).toBeDefined();
  });

  it("disables Next on step 1 until password is at least 8 characters", async () => {
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    const nextBtn = screen.getByRole("button", { name: /下一步/ }) as HTMLButtonElement;
    expect(nextBtn.disabled).toBe(true);
    await userEvent.type(screen.getByLabelText("管理员密码"), "short");
    expect(nextBtn.disabled).toBe(true);
    await userEvent.type(screen.getByLabelText("管理员密码"), "enough!!");
    expect(nextBtn.disabled).toBe(false);
  });

  it("Back navigates from step 1 to step 0", async () => {
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    fireEvent.click(screen.getByRole("button", { name: /上一步/ }));
    expect(screen.getByText(/欢迎使用 AIChat Relay/)).toBeDefined();
  });

  it("walks through steps 1→2→3 and shows the Bearer Token banner", async () => {
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    expect(screen.getByText(/Gemini API key/)).toBeDefined();
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    expect(screen.getByText("Bearer Token")).toBeDefined();
    expect(screen.getByRole("button", { name: /创建并登录/ })).toBeDefined();
  });

  it("Back from step 2 returns to step 1", async () => {
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /上一步/ }));
    expect(screen.getByLabelText("管理员密码")).toBeDefined();
  });

  it("posts to /api/admin/setup and advances to step 4 on success", async () => {
    const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /创建并登录/ }));
    await waitFor(() => expect(screen.getByText("部署完成")).toBeDefined());
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/admin/setup",
      expect.objectContaining({
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: "admin", password: "longenough" }),
      }),
    );
  });

  it("does not advance past step 3 when /api/admin/setup returns an error response", async () => {
    const fetchMock = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "已经初始化过" }), {
          status: 409,
          headers: { "Content-Type": "application/json" },
        }),
    );
    vi.stubGlobal("fetch", fetchMock);
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /创建并登录/ }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    // Step 3 banner is still visible — we did not advance to step 4 ("部署完成").
    expect(screen.getByText("Bearer Token")).toBeDefined();
    expect(screen.queryByText("部署完成")).toBeNull();
  });

  it("recovers cleanly when the failure response body is not JSON", async () => {
    const fetchMock = vi.fn(async () => new Response("not json", { status: 500 }));
    vi.stubGlobal("fetch", fetchMock);
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /创建并登录/ }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    // Stays on the Bearer Token step instead of throwing.
    expect(screen.getByText("Bearer Token")).toBeDefined();
    expect(screen.queryByText("部署完成")).toBeNull();
  });

  it("from the success step, Dashboard CTA pushes to /dashboard", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 200 })));
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /创建并登录/ }));
    await waitFor(() => expect(screen.getByText("部署完成")).toBeDefined());
    fireEvent.click(screen.getByRole("button", { name: /进入 Dashboard/ }));
    expect(pushMock).toHaveBeenCalledWith("/dashboard");
  });

  it("Back from step 3 returns to step 2", async () => {
    render(<SetupForm />);
    fireEvent.click(screen.getByRole("button", { name: /开始/ }));
    await userEvent.type(screen.getByLabelText("管理员密码"), "longenough");
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /下一步/ }));
    fireEvent.click(screen.getByRole("button", { name: /上一步/ }));
    expect(screen.getByText(/Gemini API key/)).toBeDefined();
  });
});
