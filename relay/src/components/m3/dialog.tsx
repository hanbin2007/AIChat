"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { IconButton } from "./icon-button";

export function Dialog({
  open,
  onClose,
  title,
  icon,
  children,
  actions,
  className,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  icon?: string;
  children?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  React.useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-scrim/40 p-4 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cn(
          "w-full max-w-md rounded-m3-xl bg-surface-container-high p-6 shadow-2xl",
          className,
        )}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-2 flex items-center gap-3">
          <h2 className="text-m3-headline-s text-on-surface flex-1">{title}</h2>
          <IconButton icon="close" size="sm" onClick={onClose} aria-label="Close" />
        </div>
        <div className="mb-6 text-m3-body-m text-on-surface-variant">{children}</div>
        {actions && <div className="flex justify-end gap-2">{actions}</div>}
      </div>
    </div>
  );
}
