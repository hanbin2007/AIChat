import * as React from "react";
import { cn } from "@/lib/cn";

type Tone = "neutral" | "success" | "warn" | "error" | "info";

const TONES: Record<Tone, string> = {
  neutral: "bg-surface-container-highest text-on-surface-variant",
  success: "bg-secondary-container text-on-secondary-container",
  warn: "bg-tertiary-container text-on-tertiary-container",
  error: "bg-error-container text-on-error-container",
  info: "bg-primary-container text-on-primary-container",
};

export function Badge({
  tone = "neutral",
  className,
  children,
}: {
  tone?: Tone;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <span
      className={cn(
        "inline-flex h-5 items-center rounded-full px-2 text-m3-label-s font-medium",
        TONES[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}
