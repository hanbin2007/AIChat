"use client";
import * as React from "react";
import { cn } from "@/lib/cn";

export interface SwitchProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "size" | "type"> {
  label?: string;
  supporting?: string;
}

export const Switch = React.forwardRef<HTMLInputElement, SwitchProps>(function Switch(
  { label, supporting, className, checked, ...props },
  ref,
) {
  return (
    <label className={cn("flex cursor-pointer items-start gap-4", className)}>
      <span className="relative inline-flex h-8 w-13 shrink-0 items-center">
        <input
          ref={ref}
          type="checkbox"
          checked={checked}
          {...props}
          className="peer sr-only"
        />
        <span
          aria-hidden
          className={cn(
            "h-8 w-[3.25rem] rounded-full transition-colors duration-m3-short3",
            checked
              ? "bg-primary"
              : "bg-surface-container-highest border-2 border-outline",
          )}
        />
        <span
          aria-hidden
          className={cn(
            "absolute left-1 top-1/2 -translate-y-1/2 rounded-full transition-all duration-m3-short3",
            checked
              ? "left-[1.5rem] h-6 w-6 bg-on-primary"
              : "h-4 w-4 bg-outline",
          )}
        />
      </span>
      {(label || supporting) && (
        <span className="flex flex-col">
          {label && <span className="text-m3-body-l text-on-surface">{label}</span>}
          {supporting && <span className="text-m3-body-s text-on-surface-variant">{supporting}</span>}
        </span>
      )}
    </label>
  );
});
