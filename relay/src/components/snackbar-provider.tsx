"use client";

import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";
import IconButton from "@mui/material/IconButton";
import CloseRounded from "@mui/icons-material/CloseRounded";

export type SnackbarSeverity = "info" | "success" | "warning" | "error";

export interface SnackbarMessage {
  message: string;
  severity?: SnackbarSeverity;
  durationMs?: number;
}

interface SnackbarContextValue {
  push: (msg: SnackbarMessage) => void;
}

const SnackbarContext = createContext<SnackbarContextValue | null>(null);

export function useSnackbar(): SnackbarContextValue {
  const ctx = useContext(SnackbarContext);
  if (!ctx) throw new Error("useSnackbar must be used inside <SnackbarProvider>");
  return ctx;
}

export function SnackbarProvider({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const [current, setCurrent] = useState<SnackbarMessage | null>(null);
  const queue = useRef<SnackbarMessage[]>([]);

  const showNext = useCallback(() => {
    const next = queue.current.shift();
    if (next) {
      setCurrent(next);
      setOpen(true);
    } else {
      setCurrent(null);
    }
  }, []);

  const push = useCallback(
    (msg: SnackbarMessage) => {
      queue.current.push(msg);
      if (!open && !current) showNext();
    },
    [open, current, showNext],
  );

  const handleClose = useCallback((_event?: unknown, reason?: string) => {
    if (reason === "clickaway") return;
    setOpen(false);
  }, []);

  const handleExited = useCallback(() => {
    showNext();
  }, [showNext]);

  const ctx = useMemo<SnackbarContextValue>(() => ({ push }), [push]);

  return (
    <SnackbarContext.Provider value={ctx}>
      {children}
      <Snackbar
        open={open}
        autoHideDuration={current?.durationMs ?? 4000}
        onClose={handleClose}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
        slotProps={{ transition: { onExited: handleExited } }}
      >
        {current ? (
          <Alert
            severity={current.severity ?? "info"}
            variant="filled"
            sx={{ minWidth: 280 }}
            action={
              <IconButton
                aria-label="关闭"
                size="small"
                color="inherit"
                onClick={() => setOpen(false)}
              >
                <CloseRounded fontSize="small" />
              </IconButton>
            }
          >
            {current.message}
          </Alert>
        ) : undefined}
      </Snackbar>
    </SnackbarContext.Provider>
  );
}
