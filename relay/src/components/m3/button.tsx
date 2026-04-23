"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

type Variant = "filled" | "tonal" | "elevated" | "outlined" | "text";

const VARIANT_CLASSES: Record<Variant, string> = {
  filled: "bg-primary text-on-primary hover:shadow-sm",
  tonal: "bg-secondary-container text-on-secondary-container",
  elevated: "bg-surface-container-low text-primary shadow-sm hover:shadow",
  outlined: "bg-transparent text-primary border border-outline hover:border-primary",
  text: "bg-transparent text-primary",
};

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  icon?: string;
  trailing?: string;
  loading?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = "filled", icon, trailing, loading, className, children, disabled, ...props },
  ref,
) {
  return (
    <button
      ref={ref}
      disabled={disabled || loading}
      className={cn(
        "state-layer inline-flex h-10 items-center gap-2 rounded-full px-6 text-m3-label-l font-medium transition-all duration-m3-short3 ease-m3-standard disabled:pointer-events-none disabled:opacity-40",
        VARIANT_CLASSES[variant],
        icon && !children && "w-10 px-0 justify-center",
        icon && children && "pl-4",
        trailing && "pr-4",
        className,
      )}
      {...props}
    >
      {loading ? (
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
      ) : icon ? (
        <Icon name={icon} size={18} />
      ) : null}
      {children}
      {trailing && <Icon name={trailing} size={18} />}
    </button>
  );
});
