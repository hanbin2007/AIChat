"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
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
  const [queue, setQueue] = useState<SnackbarMessage[]>([]);

  const push = useCallback((msg: SnackbarMessage) => {
    setQueue((items) => [...items, msg]);
  }, []);

  useEffect(() => {
    if (open || current || queue.length === 0) return;
    const [next, ...rest] = queue;
    setCurrent(next);
    setQueue(rest);
    setOpen(true);
  }, [current, open, queue]);

  const handleClose = useCallback((_event?: unknown, reason?: string) => {
    if (reason === "clickaway") return;
    setOpen(false);
  }, []);

  const handleExited = useCallback(() => {
    setCurrent(null);
  }, []);

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
