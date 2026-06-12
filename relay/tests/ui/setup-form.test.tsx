import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import SetupForm from "@/app/setup/setup-form";

const replace = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({
    replace,
  }),
}));

async function completeRequiredSteps() {
  const user = userEvent.setup();

  await user.click(screen.getByRole("button", { name: "开始" }));
  await user.type(screen.getByLabelText("用户名"), "admin");
  await user.type(screen.getByLabelText("密码（至少 8 位）"), "newpassword");
  await user.type(screen.getByLabelText("确认密码"), "newpassword");
  await user.click(screen.getByRole("button", { name: "下一步" }));
  await user.click(screen.getByRole("button", { name: "下一步" }));
  await user.click(screen.getByRole("button", { name: "创建管理员并进入控制台" }));
  return user;
}

describe("SetupForm", () => {
  beforeEach(() => {
    replace.mockClear();
    vi.unstubAllGlobals();
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("redirects to the dashboard after setup without posting credentials to login", async () => {
    const fetch = vi.fn(async (url: RequestInfo | URL) => {
      if (url === "/api/admin/setup") {
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ message: "unexpected" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    });
    vi.stubGlobal("fetch", fetch);

    render(<SetupForm />);

    await completeRequiredSteps();

    await waitFor(() => expect(replace).toHaveBeenCalledWith("/dashboard"));
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(fetch).toHaveBeenCalledWith(
      "/api/admin/setup",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ username: "admin", password: "newpassword" }),
      }),
    );
    expect(fetch).not.toHaveBeenCalledWith(
      "/api/admin/login",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("offers stable recovery links when setup is already complete", async () => {
    const fetch = vi.fn(async () => (
      new Response(JSON.stringify({ message: "Setup already complete." }), {
        status: 409,
        headers: { "Content-Type": "application/json" },
      })
    ));
    vi.stubGlobal("fetch", fetch);

    render(<SetupForm />);

    const user = await completeRequiredSteps();

    expect(await screen.findByText("初始化已完成。请前往登录页，或直接进入控制台。")).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "前往登录" }));
    expect(replace).toHaveBeenCalledWith("/login");
    await user.click(screen.getByRole("button", { name: "进入控制台" }));
    expect(replace).toHaveBeenCalledWith("/dashboard");
  });

  it("marks setup passwords as new passwords and exposes helper text", async () => {
    const user = userEvent.setup();
    render(<SetupForm />);

    await user.click(screen.getByRole("button", { name: "开始" }));

    expect(screen.getByLabelText("用户名").getAttribute("autocomplete")).toBe("username");
    expect(screen.getByLabelText("密码（至少 8 位）").getAttribute("autocomplete")).toBe("new-password");
    expect(screen.getByLabelText("确认密码").getAttribute("autocomplete")).toBe("new-password");
    expect(screen.getByText("至少 8 位，建议使用独立强密码。")).toBeTruthy();
    expect(screen.getByText("请再次输入新密码。")).toBeTruthy();
  });
});
