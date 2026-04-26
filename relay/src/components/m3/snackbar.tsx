"use client";
import * as React from "react";
import { cn } from "@/lib/cn";

type Snack = { id: number; message: string; action?: { label: string; onClick: () => void } };

const SnackCtx = React.createContext<{ push: (s: Omit<Snack, "id">) => void } | null>(null);

export function SnackbarProvider({ children }: { children: React.ReactNode }) {
  const [queue, setQueue] = React.useState<Snack[]>([]);
  const push = React.useCallback((s: Omit<Snack, "id">) => {
    const id = Date.now() + Math.random();
    setQueue((q) => [...q, { ...s, id }]);
    setTimeout(() => setQueue((q) => q.filter((x) => x.id !== id)), 5000);
  }, []);
  return (
    <SnackCtx.Provider value={{ push }}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 bottom-6 z-50 flex flex-col items-center gap-2">
        {queue.map((s) => (
          <div
            key={s.id}
            className={cn(
              "pointer-events-auto flex items-center gap-3 rounded-m3-xs bg-inverse px-4 py-3 text-m3-body-m text-on-inverse shadow-lg",
            )}
          >
            <span>{s.message}</span>
            {s.action && (
              <button
                onClick={s.action.onClick}
                className="text-m3-label-l font-medium text-inverse-primary"
              >
                {s.action.label}
              </button>
            )}
          </div>
        ))}
      </div>
    </SnackCtx.Provider>
  );
}

export function useSnackbar() {
  const ctx = React.useContext(SnackCtx);
  if (!ctx) throw new Error("useSnackbar must be used inside SnackbarProvider");
  return ctx;
}
