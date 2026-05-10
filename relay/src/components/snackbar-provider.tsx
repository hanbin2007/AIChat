"use client";
import * as React from "react";
import Snackbar from "@mui/material/Snackbar";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import CloseIcon from "@mui/icons-material/Close";

type Snack = {
  id: number;
  message: string;
  action?: { label: string; onClick: () => void };
};

type Ctx = { push: (s: Omit<Snack, "id">) => void };

const SnackCtx = React.createContext<Ctx | null>(null);

export function SnackbarProvider({ children }: { children: React.ReactNode }) {
  const [queue, setQueue] = React.useState<Snack[]>([]);
  const [current, setCurrent] = React.useState<Snack | null>(null);
  const [open, setOpen] = React.useState(false);

  const push = React.useCallback((s: Omit<Snack, "id">) => {
    setQueue((q) => [...q, { ...s, id: Date.now() + Math.random() }]);
  }, []);

  React.useEffect(() => {
    if (!current && queue.length) {
      setCurrent(queue[0]);
      setQueue((q) => q.slice(1));
      setOpen(true);
    } else if (current && queue.length && open) {
      setOpen(false);
    }
  }, [queue, current, open]);

  const handleClose = (_e?: unknown, reason?: string) => {
    if (reason === "clickaway") return;
    setOpen(false);
  };

  const handleExited = () => setCurrent(null);

  return (
    <SnackCtx.Provider value={{ push }}>
      {children}
      <Snackbar
        key={current?.id ?? "empty"}
        open={open}
        autoHideDuration={5000}
        onClose={handleClose}
        TransitionProps={{ onExited: handleExited }}
        message={current?.message}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
        action={
          <>
            {current?.action && (
              <Button
                color="primary"
                size="small"
                onClick={() => {
                  current.action?.onClick();
                  handleClose();
                }}
              >
                {current.action.label}
              </Button>
            )}
            <IconButton size="small" aria-label="关闭" color="inherit" onClick={handleClose}>
              <CloseIcon fontSize="small" />
            </IconButton>
          </>
        }
      />
    </SnackCtx.Provider>
  );
}

export function useSnackbar() {
  const ctx = React.useContext(SnackCtx);
  if (!ctx) throw new Error("useSnackbar must be used inside SnackbarProvider");
  return ctx;
}
