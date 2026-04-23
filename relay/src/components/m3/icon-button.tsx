"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

type Variant = "standard" | "filled" | "tonal" | "outlined";

const CLASSES: Record<Variant, string> = {
  standard: "text-on-surface-variant hover:text-on-surface",
  filled: "bg-primary text-on-primary",
  tonal: "bg-secondary-container text-on-secondary-container",
  outlined: "border border-outline text-on-surface-variant",
};

export interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  icon: string;
  variant?: Variant;
  filled?: boolean;
  size?: "sm" | "md" | "lg";
  toggled?: boolean;
}

export const IconButton = React.forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { icon, variant = "standard", filled, size = "md", toggled, className, ...props },
  ref,
) {
  const dim = size === "sm" ? "h-8 w-8" : size === "lg" ? "h-12 w-12" : "h-10 w-10";
  const glyph = size === "sm" ? 18 : size === "lg" ? 26 : 22;
  return (
    <button
      ref={ref}
      aria-pressed={toggled}
      className={cn(
        "state-layer inline-flex items-center justify-center rounded-full transition-colors duration-m3-short3",
        dim,
        CLASSES[variant],
        toggled && "bg-primary-container text-on-primary-container",
        className,
      )}
      {...props}
    >
      <Icon name={icon} size={glyph} filled={filled || toggled} />
    </button>
  );
});
