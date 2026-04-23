"use client";
import * as React from "react";
import { cn } from "@/lib/cn";

export function Tabs<T extends string>({
  options,
  value,
  onChange,
  variant = "primary",
  className,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
  variant?: "primary" | "secondary";
  className?: string;
}) {
  return (
    <div className={cn("relative flex border-b border-outline-variant", className)}>
      {options.map((opt) => {
        const active = opt.value === value;
        return (
          <button
            key={opt.value}
            role="tab"
            aria-selected={active}
            onClick={() => onChange(opt.value)}
            className={cn(
              "state-layer relative h-12 px-4 text-m3-label-l font-medium transition-colors duration-m3-short3",
              active
                ? variant === "primary"
                  ? "text-primary"
                  : "text-on-surface"
                : "text-on-surface-variant",
            )}
          >
            {opt.label}
            {active && (
              <span
                aria-hidden
                className={cn(
                  "absolute inset-x-3 -bottom-px h-0.5 rounded-full",
                  variant === "primary" ? "bg-primary" : "bg-on-surface",
                )}
              />
            )}
          </button>
        );
      })}
    </div>
  );
}
