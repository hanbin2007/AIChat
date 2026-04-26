"use client";
import * as React from "react";
import { cn } from "@/lib/cn";
import { Icon } from "./icon";

type Variant = "assist" | "filter" | "input" | "suggestion";

export interface ChipProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  selected?: boolean;
  icon?: string;
  trailing?: string;
  onRemove?: () => void;
}

const BASE = "state-layer inline-flex h-8 items-center gap-1.5 rounded-m3-sm px-3 text-m3-label-l font-medium transition-colors duration-m3-short3";

export function Chip({
  variant = "filter",
  selected,
  icon,
  trailing,
  onRemove,
  className,
  children,
  ...props
}: ChipProps) {
  const selectedClasses = selected
    ? "bg-secondary-container text-on-secondary-container"
    : variant === "input"
      ? "bg-surface-container-high text-on-surface"
      : "border border-outline bg-transparent text-on-surface-variant";
  return (
    <button
      type="button"
      aria-pressed={variant === "filter" ? !!selected : undefined}
      className={cn(BASE, selectedClasses, className)}
      {...props}
    >
      {selected && variant === "filter" ? (
        <Icon name="check" size={16} />
      ) : icon ? (
        <Icon name={icon} size={16} />
      ) : null}
      <span>{children}</span>
      {trailing && <Icon name={trailing} size={16} />}
      {onRemove && (
        <span
          role="button"
          aria-label="Remove"
          onClick={(e) => {
            e.stopPropagation();
            onRemove();
          }}
          className="ml-1 rounded-full p-0.5 hover:bg-on-surface/10"
        >
          <Icon name="close" size={14} />
        </span>
      )}
    </button>
  );
}
