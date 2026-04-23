"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

export interface FabProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  icon: string;
  label?: string;
  size?: "sm" | "md" | "lg";
}

export const Fab = React.forwardRef<HTMLButtonElement, FabProps>(function Fab(
  { icon, label, size = "md", className, ...props },
  ref,
) {
  const extended = !!label;
  const dim = size === "sm" ? "h-10 min-w-10" : size === "lg" ? "h-24 min-w-24" : "h-14 min-w-14";
  const glyph = size === "sm" ? 20 : size === "lg" ? 36 : 24;
  return (
    <button
      ref={ref}
      className={cn(
        "state-layer inline-flex items-center justify-center gap-3 rounded-2xl bg-primary-container text-on-primary-container shadow-md transition-all duration-m3-short3 hover:shadow-lg",
        dim,
        extended ? "px-5" : "px-0 aspect-square",
        className,
      )}
      {...props}
    >
      <Icon name={icon} size={glyph} />
      {extended && <span className="pr-1 text-m3-label-l font-medium">{label}</span>}
    </button>
  );
});
