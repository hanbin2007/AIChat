import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import PlaygroundPage from "@/app/(admin)/playground/page";

const encoder = new TextEncoder();

function streamResponse(chunks: string[]): Response {
  return new Response(
    new ReadableStream({
      start(controller) {
        for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
        controller.close();
      },
    }),
    { status: 200, headers: { "Content-Type": "text/event-stream" } },
  );
}

function sse(event: string, data: Record<string, unknown>): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

describe("PlaygroundPage", () => {
  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("keeps raw SSE hidden by default and toggles the masked Authorization field", async () => {
    const user = userEvent.setup();
    render(<PlaygroundPage />);

    expect(screen.queryByText("原始 SSE 事件")).toBeNull();
    const authorization = screen.getByLabelText("Authorization (可选)");
    expect(authorization.getAttribute("type")).toBe("password");

    await user.click(screen.getByRole("button", { name: "显示 Authorization" }));
    expect(authorization.getAttribute("type")).toBe("text");

    await user.click(screen.getByRole("button", { name: "隐藏 Authorization" }));
    expect(authorization.getAttribute("type")).toBe("password");
  });

  it("normalizes bearer tokens and reads text / finishReason stream fields", async () => {
    const fetchMock = vi.fn(async () =>
      streamResponse([
        sse("answer_delta", { type: "answer_delta", text: "Hello" }),
        sse("done", { type: "done", finishReason: "MAX_TOKENS" }),
      ]),
    );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();

    render(<PlaygroundPage />);

    await user.type(screen.getByLabelText("Authorization (可选)"), "Bearer test-token");
    await user.type(screen.getByPlaceholderText("输入消息…（Enter 发送，Shift+Enter 换行）"), "hi");
    await user.click(screen.getByRole("button", { name: "发送" }));

    await screen.findByText("Hello");
    await screen.findByText("finishReason: MAX_TOKENS");
    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect((init.headers as Record<string, string>).Authorization).toBe("Bearer test-token");
    expect(JSON.parse(init.body as string).messages).toEqual([{ role: "user", text: "hi" }]);
  });

  it("shows an error when the stream ends without done or error", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => streamResponse([])));
    const user = userEvent.setup();

    render(<PlaygroundPage />);

    await user.type(screen.getByPlaceholderText("输入消息…（Enter 发送，Shift+Enter 换行）"), "hi");
    await user.click(screen.getByRole("button", { name: "发送" }));

    await waitFor(() => {
      expect(screen.getByText("流已断开，未收到完成或错误事件。")).toBeTruthy();
    });
  });

  it("aborts the active stream from the cancel button", async () => {
    let signal: AbortSignal | undefined;
    const fetchMock = vi.fn(
      (_url: string, init: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          signal = init.signal as AbortSignal;
          signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
        }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();

    render(<PlaygroundPage />);

    await user.type(screen.getByPlaceholderText("输入消息…（Enter 发送，Shift+Enter 换行）"), "hi");
    await user.click(screen.getByRole("button", { name: "发送" }));
    await user.click(await screen.findByRole("button", { name: "取消" }));

    expect(signal?.aborted).toBe(true);
    await screen.findByText("请求已取消。");
  });
});
