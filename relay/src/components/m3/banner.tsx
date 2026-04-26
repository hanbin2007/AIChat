import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

type Tone = "info" | "warn" | "error" | "success";

const TONES: Record<Tone, { bg: string; text: string; icon: string }> = {
  info: { bg: "bg-primary-container", text: "text-on-primary-container", icon: "info" },
  warn: { bg: "bg-tertiary-container", text: "text-on-tertiary-container", icon: "warning" },
  error: { bg: "bg-error-container", text: "text-on-error-container", icon: "error" },
  success: { bg: "bg-secondary-container", text: "text-on-secondary-container", icon: "check_circle" },
};

export function Banner({
  tone = "info",
  title,
  children,
  actions,
  className,
}: {
  tone?: Tone;
  title?: string;
  children?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  const t = TONES[tone];
  return (
    <div className={cn("rounded-m3-md px-4 py-3 flex items-start gap-3", t.bg, t.text, className)}>
      <Icon name={t.icon} size={22} className="mt-0.5 shrink-0" />
      <div className="flex-1">
        {title && <div className="text-m3-title-s font-medium">{title}</div>}
        <div className="text-m3-body-m opacity-90">{children}</div>
      </div>
      {actions && <div className="shrink-0 flex items-center gap-1">{actions}</div>}
    </div>
  );
}
