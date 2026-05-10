import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as React from "react";
import { ThemeProvider } from "@mui/material/styles";
import CssBaseline from "@mui/material/CssBaseline";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogActions from "@mui/material/DialogActions";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";
import Tabs from "@mui/material/Tabs";
import Tab from "@mui/material/Tab";
import { theme } from "@/theme";
import { SnackbarProvider, useSnackbar } from "@/components/snackbar-provider";

function withTheme(node: React.ReactElement) {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      {node}
    </ThemeProvider>
  );
}

afterEach(cleanup);

describe("Theme provider", () => {
  it("renders children without throwing", () => {
    render(withTheme(<Button>登录</Button>));
    expect(screen.getByRole("button", { name: "登录" })).toBeDefined();
  });
});

describe("MuiButton", () => {
  it("invokes onClick on press", async () => {
    const onClick = vi.fn();
    render(withTheme(<Button onClick={onClick}>保存</Button>));
    await userEvent.click(screen.getByRole("button", { name: /保存/ }));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it("does not fire click when disabled", () => {
    const onClick = vi.fn();
    render(withTheme(<Button disabled onClick={onClick}>保存</Button>));
    // user-event v14 refuses to dispatch on pointer-events:none; use fireEvent
    // to simulate a programmatic click and assert the handler is suppressed.
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).not.toHaveBeenCalled();
  });
});

describe("MuiDialog", () => {
  it("renders nothing when closed", () => {
    const { container } = render(
      withTheme(
        <Dialog open={false} onClose={() => {}}>
          <DialogTitle>x</DialogTitle>
        </Dialog>,
      ),
    );
    expect(container.querySelector('[role="dialog"]')).toBeNull();
  });

  it("invokes onClose when Escape is pressed", () => {
    const onClose = vi.fn();
    render(
      withTheme(
        <Dialog open onClose={onClose}>
          <DialogTitle>测试对话</DialogTitle>
          <DialogContent>body</DialogContent>
          <DialogActions>
            <Button onClick={onClose}>关闭</Button>
          </DialogActions>
        </Dialog>,
      ),
    );
    fireEvent.keyDown(document.activeElement ?? document.body, { key: "Escape" });
    expect(onClose).toHaveBeenCalled();
  });

  it("renders the title and a primary action", () => {
    render(
      withTheme(
        <Dialog open onClose={() => {}}>
          <DialogTitle>编辑账户</DialogTitle>
          <DialogContent>正文</DialogContent>
          <DialogActions>
            <Button>取消</Button>
            <Button>保存</Button>
          </DialogActions>
        </Dialog>,
      ),
    );
    expect(screen.getByText("编辑账户")).toBeDefined();
    expect(screen.getByRole("button", { name: "保存" })).toBeDefined();
  });
});

describe("MuiTabs", () => {
  it("switches selection on click", async () => {
    function Harness() {
      const [v, setV] = React.useState("a");
      return (
        <>
          <Tabs value={v} onChange={(_, nv) => setV(nv as string)}>
            <Tab value="a" label="A" />
            <Tab value="b" label="B" />
          </Tabs>
          <span data-testid="active">{v}</span>
        </>
      );
    }
    render(withTheme(<Harness />));
    await userEvent.click(screen.getByRole("tab", { name: "B" }));
    expect(screen.getByTestId("active").textContent).toBe("b");
  });
});

describe("MuiSnackbar", () => {
  it("renders the message when open", () => {
    render(
      withTheme(
        <Snackbar open autoHideDuration={null} message="已保存" />,
      ),
    );
    expect(screen.getByText("已保存")).toBeDefined();
  });
});

describe("MuiAlert", () => {
  it("maps severity to a role and shows the message", () => {
    render(withTheme(<Alert severity="error">出错了</Alert>));
    expect(screen.getByRole("alert").textContent).toContain("出错了");
  });
});

describe("SnackbarProvider", () => {
  it("queues and surfaces a pushed message", async () => {
    function Harness() {
      const snack = useSnackbar();
      return <Button onClick={() => snack.push({ message: "已保存" })}>触发</Button>;
    }
    render(withTheme(<SnackbarProvider><Harness /></SnackbarProvider>));
    await userEvent.click(screen.getByRole("button", { name: "触发" }));
    expect(await screen.findByText("已保存")).toBeDefined();
  });
});
